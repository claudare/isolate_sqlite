import 'isolate_sqlite.dart';

typedef MigrationFn = Future<void> Function(IsolateSqlite db);

class SqliteMigration {
  final int version;
  final MigrationFn up;

  const SqliteMigration(this.version, this.up);
}

// TODO: implement "down" migrations?
// TODO: option to disable foreign key constraints?
class SqliteMigrations {
  final String migrationTable;
  final List<SqliteMigration> _migrations = [];

  SqliteMigrations({this.migrationTable = 'migrations'});

  void add(SqliteMigration migration) {
    _migrations.add(migration);
  }

  Future<void> migrate(IsolateSqlite db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $migrationTable (
        version INTEGER PRIMARY KEY,
        applied_at TEXT NOT NULL
      )
    ''');

    final applied = await db.query(
      'SELECT version FROM $migrationTable ORDER BY version',
    );
    final appliedSet = applied.map((r) => r[0] as int).toSet();

    final pending = _migrations..sort((a, b) => a.version.compareTo(b.version));

    for (final m in pending) {
      if (appliedSet.contains(m.version)) continue;

      await db.execute('BEGIN');
      try {
        await m.up(db);
        await db.execute(
          'INSERT INTO $migrationTable (version, applied_at) VALUES (?, CURRENT_TIMESTAMP)',
          [m.version],
        );
        await db.execute('COMMIT');
      } catch (e) {
        await db.execute('ROLLBACK');
        rethrow;
      }
    }
  }
}
