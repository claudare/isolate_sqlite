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

class TodoRepo extends IsolateSqlite {
  TodoRepo(super.initFn);

  Future<void> migrate() async {
    await execute(
      'CREATE TABLE todo (id TEXT PRIMARY KEY, name TEXT NOT NULL)',
    );
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
    final row = await queryRow(
      'SELECT id, name FROM todo WHERE id = ? LIMIT 1',
      [id],
    );
    if (row == null) return null;

    return Todo(row[0] as String, row[1] as String);
  }

  Future<List<Todo>> getAll() async {
    final rows = await query('SELECT id, name FROM todo ORDER BY id');
    return [for (final r in rows) Todo(r[0] as String, r[1] as String)];
  }

  Future<int> count() async =>
      await queryValue<int>('SELECT COUNT(*) FROM todo') ?? 0;

  Future<void> deleteById(String id) =>
      execute('DELETE FROM todo WHERE id = ?', [id]);

  Future<void> update(Todo todo) =>
      execute('UPDATE todo SET name = ? WHERE id = ?', [todo.name, todo.id]);
}

// ── Tests ───────────────────────────────────────────────────────────

void main() {
  late TodoRepo repo;

  setUp(() async {
    repo = TodoRepo(() => sqlite3.openInMemory());
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
