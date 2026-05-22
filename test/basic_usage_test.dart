import 'package:test/test.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';

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

class TodoRepo {
  final IsolateSqlite _db;

  const TodoRepo(this._db);

  Future<void> migrate() async {
    await _db.execute(
      'CREATE TABLE todo (id TEXT PRIMARY KEY, name TEXT NOT NULL)',
    );
  }

  Future<void> insert(Todo todo) => _db.execute(
    'INSERT INTO todo (id, name) VALUES (?, ?)',
    [todo.id, todo.name],
  );

  Future<ExecuteResult> insertMany(List<Todo> todos) {
    final sql =
        'INSERT INTO todo (id, name) VALUES ${todos.map((t) => '(?, ?)').join(', ')}';
    final args = todos.expand((todo) => [todo.id, todo.name]).toList();

    return _db.execute(sql, args);
  }

  Future<ExecuteResult> upsert(Todo todo) => _db.execute(
    'INSERT INTO todo (id, name) VALUES (?, ?) ON CONFLICT(id) DO UPDATE SET name = ?',
    [todo.id, todo.name, todo.name],
  );

  Future<Todo?> getById(String id) async {
    final row = await _db.queryRow(
      'SELECT id, name FROM todo WHERE id = ? LIMIT 1',
      [id],
    );
    if (row == null) return null;

    return Todo(row[0] as String, row[1] as String);
  }

  Future<List<Todo>> getAll() async {
    final rows = await _db.query('SELECT id, name FROM todo ORDER BY id');
    return rows.map((r) => Todo(r.field('id'), r.field('name'))).toList();
  }

  Future<List<Todo>> getAllRows() async {
    final rows = await _db.transaction(
      (tx) => tx.query('SELECT id, name FROM todo ORDER BY id'),
    );
    return [for (final r in rows) Todo(r.field('id'), r.field('name'))];
  }

  Future<int> count() => _db.queryValue<int>('SELECT COUNT(*) FROM todo');

  Future<ExecuteResult> deleteById(String id) =>
      _db.execute('DELETE FROM todo WHERE id = ?', [id]);

  Future<ExecuteResult> update(Todo todo) => _db.execute(
    'UPDATE todo SET name = ? WHERE id = ?',
    [todo.name, todo.id],
  );
}

// ── Tests ───────────────────────────────────────────────────────────

void main() {
  late IsolateSqlite db;
  late TodoRepo repo;

  setUp(() async {
    db = IsolateSqlite();
    repo = TodoRepo(db);
    await db.openInMemory();
    await repo.migrate();
  });

  tearDown(() async {
    await db.close();
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
    await repo.insertMany([
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

  test('getAll returns all inserted rows in order (new method)', () async {
    final result = await repo.insertMany([
      const Todo('2', 'Second'),
      const Todo('1', 'First'),
      const Todo('3', 'Third'),
    ]);
    expect(result.modified, 3);
    expect(result.rowId, 3);

    final todos = await repo.getAllRows();

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
    await repo.insertMany([const Todo('1', 'Keep'), const Todo('2', 'Remove')]);

    final result = await repo.deleteById('2');
    expect(result.modified, 1);

    expect(await repo.getById('1'), isNotNull);
    expect(await repo.getById('2'), isNull);
  });

  test('update modifies existing row', () async {
    await repo.insert(const Todo('1', 'Old name'));

    final result = await repo.update(const Todo('1', 'New name'));
    expect(result.modified, 1);

    final todo = await repo.getById('1');
    expect(todo, equals(const Todo('1', 'New name')));
  });

  test('duplicate insert throws', () async {
    await repo.insert(const Todo('1', 'First'));

    expect(() => repo.insert(const Todo('1', 'Duplicate')), throwsException);
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
}
