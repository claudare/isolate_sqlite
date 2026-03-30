import 'package:test/test.dart';

import 'package:isolate_sqlite/isolate_sqlite.dart';

class TestDb extends IsolateSqlite {
  TestDb() : super(IsolateSqlite.memoryInitFn);
}

void main() {
  late TestDb db;

  setUp(() async {
    db = TestDb();
    await db.open();
  });

  tearDown(() async {
    await db.close();
  });

  test('applies pending migrations once, in order', () async {
    final migrations = SqliteMigrations(migrationTable: 'test_migrations')
      ..add(
        SqliteMigration(1, (tx) async {
          await tx.exec('CREATE TABLE t1 (id TEXT PRIMARY KEY)');
        }),
      )
      ..add(
        SqliteMigration(2, (tx) async {
          await tx.exec('ALTER TABLE t1 ADD COLUMN name TEXT');
        }),
      )
      ..add(
        SqliteMigration(3, (tx) async {
          await tx.exec('CREATE TABLE t2 (id INTEGER PRIMARY KEY)');
        }),
      );

    // first run
    await migrations.migrate(db);

    // tables exist
    final tables = await db.query(
      "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
    );
    final names = tables.map((r) => r[0] as String).toList();
    expect(names, containsAll(['t1', 't2', 'test_migrations']));

    // migration rows
    final applied = await db.query(
      'SELECT version FROM test_migrations ORDER BY version',
    );
    expect(applied.map((r) => r[0]), [1, 2, 3]);

    // second run should do nothing
    await migrations.migrate(db);

    final applied2 = await db.query(
      'SELECT version FROM test_migrations ORDER BY version',
    );
    expect(applied2.length, 3);
  });
}
