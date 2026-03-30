import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:isolated_sqlite/isolated_sqlite.dart';

// ── Test model ──────────────────────────────────────────────────────

class Todo {
  final String id;
  final String name;
  const Todo(this.id, this.name);

  @override
  bool operator ==(Object other) =>
      other is Todo && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);

  @override
  String toString() => 'Todo($id, $name)';
}

// ── Concrete repo for testing ───────────────────────────────────────

// custom counter with sideeffect
class IdGen {
  int _counter = 0;

  IdGen(this._counter);

  String nextId() {
    return '${_counter++}';
  }
}

class TodoRepo extends IsolateSqlite {
  final int _startSeq;

  TodoRepo(this._startSeq) : super.memory();

  @override
  IsolateInitFn? get onIsolateInit {
    // ⚠️ Copy to local — do NOT capture `this`
    final startSeq = _startSeq;

    return (db) {
      // This entire block runs inside the isolate.
      // Sideeffect classes are BORN here and they LIVE here.
      final idGen = IdGen(startSeq);

      db.createFunction(
        functionName: 'next_id',
        argumentCount: const AllowedArgumentCount(0),
        function: (_) => idGen.nextId(),
      );
      db.createFunction(
        functionName: 'double_it',
        argumentCount: const AllowedArgumentCount(1),
        function: (args) => (args[0] as int) * 2,
      );
      db.createFunction(
        functionName: 'is_ios',
        argumentCount: const AllowedArgumentCount(0),
        function: (_) => Platform.isIOS, // NEVER!
      );
    };
  }

  Future<void> migrate() async {
    await execute(
      'CREATE TABLE todo (id TEXT PRIMARY KEY, name TEXT NOT NULL)',
    );
    await enableOptimizations();
  }

  Future<void> insert(Todo todo) => execute(
    'INSERT INTO todo (id, name) VALUES (?, ?)',
    [todo.id, todo.name],
  );

  Future<void> insertAll(List<Todo> todos) async {
    for (final t in todos) {
      await insert(t);
    }
  }

  Future<Todo?> getById(String id) async {
    final row = await selectOne(
      'SELECT id, name FROM todo WHERE id = ? LIMIT 1',
      [id],
    );
    if (row == null) return null;

    return Todo(row[0] as String, row[1] as String);
  }

  Future<List<Todo>> getAll() async {
    final rows = await select('SELECT id, name FROM todo ORDER BY id');
    return [for (final r in rows) Todo(r[0] as String, r[1] as String)];
  }

  Future<int> count() async =>
      await selectValue<int>('SELECT COUNT(*) FROM todo') ?? 0;

  Future<void> deleteById(String id) =>
      execute('DELETE FROM todo WHERE id = ?', [id]);

  Future<void> update(Todo todo) =>
      execute('UPDATE todo SET name = ? WHERE id = ?', [todo.name, todo.id]);

  Future<void> badQuery() => execute('NOT VALID SQL !!!');

  Future<String> nextId() async {
    final rows = await select('SELECT next_id()');
    return rows[0][0] as String;
  }

  Future<int> doubleIt(int value) async {
    final rows = await select('SELECT double_it(?)', [value]);
    return rows[0][0] as int;
  }

  Future<bool> isIos() async {
    final rows = await select('SELECT is_ios()');
    return (rows[0][0] as int) == 1;
  }
}

// ── Tests ───────────────────────────────────────────────────────────

void main() {
  late TodoRepo repo;

  setUp(() async {
    repo = TodoRepo(100);
    await repo.open();
    await repo.migrate();
  });

  tearDown(() async {
    await repo.close();
  });

  test('insert and retrieve by id', () async {
    await repo.insert(const Todo('1', 'Buy milk'));

    final todo = await repo.getById('1');

    expect(todo, equals(const Todo('1', 'Buy milk')));
  });

  test('getById returns null for missing row', () async {
    final todo = await repo.getById('nonexistent');

    expect(todo, isNull);
  });

  test('getAll returns empty list on empty table', () async {
    final todos = await repo.getAll();

    expect(todos, isEmpty);
  });

  test('getAll returns all inserted rows in order', () async {
    await repo.insertAll([
      const Todo('2', 'Second'),
      const Todo('1', 'First'),
      const Todo('3', 'Third'),
    ]);

    final todos = await repo.getAll();

    expect(todos, [
      const Todo('1', 'First'),
      const Todo('2', 'Second'),
      const Todo('3', 'Third'),
    ]);
  });

  test('count reflects inserts and deletes', () async {
    expect(await repo.count(), 0);

    await repo.insert(const Todo('1', 'A'));
    await repo.insert(const Todo('2', 'B'));
    expect(await repo.count(), 2);

    await repo.deleteById('1');
    expect(await repo.count(), 1);
  });

  test('delete removes the correct row', () async {
    await repo.insertAll([const Todo('1', 'Keep'), const Todo('2', 'Remove')]);

    await repo.deleteById('2');

    expect(await repo.getById('1'), isNotNull);
    expect(await repo.getById('2'), isNull);
  });

  test('update modifies existing row', () async {
    await repo.insert(const Todo('1', 'Old name'));

    await repo.update(const Todo('1', 'New name'));

    final todo = await repo.getById('1');
    expect(todo, equals(const Todo('1', 'New name')));
  });

  test('duplicate insert throws', () async {
    await repo.insert(const Todo('1', 'First'));

    expect(() => repo.insert(const Todo('1', 'Duplicate')), throwsException);
  });

  test('invalid SQL throws', () async {
    expect(() => repo.badQuery(), throwsException);
  });

  test('operations work sequentially across many calls', () async {
    for (var i = 0; i < 50; i++) {
      await repo.insert(Todo('id_$i', 'Task $i'));
    }

    expect(await repo.count(), 50);

    final first = await repo.getById('id_0');
    final last = await repo.getById('id_49');
    expect(first?.name, 'Task 0');
    expect(last?.name, 'Task 49');
  });

  test('select with no params works', () async {
    await repo.insert(const Todo('1', 'Only'));

    final all = await repo.getAll();

    expect(all, hasLength(1));
  });

  group("createFunction", () {
    test("side-effects work across isolate boundaries", () async {
      expect(await repo.nextId(), "100");
      expect(await repo.nextId(), "101");
      expect(await repo.nextId(), "102");
    });

    test("can use arguments", () async {
      expect(await repo.doubleIt(42), 84);
    });

    test("can access fat away sideeffects", () async {
      expect(await repo.isIos(), false);
    });
  });
}
