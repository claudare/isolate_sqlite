import 'isolate_sqlite.dart';

typedef MigrationFn = void Function(Transaction tx);

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

  // TODO: pass a transaction instead of the database and make migrate sync.
  // Currently concurrent operations will fail as transaction will include them too.
  // TODO: execute all migrations under a single transcation. All or nothing.
  Future<void> migrate(IsolateSqlite db) async {
    await db.transaction((tx) {
      tx.execute('''
        CREATE TABLE IF NOT EXISTS $migrationTable (
          version INTEGER PRIMARY KEY,
          applied_at TEXT NOT NULL
        )
      ''');

      final applied = tx.query(
        'SELECT version FROM $migrationTable ORDER BY version',
      );
      final appliedSet = applied.map((r) => r[0] as int).toSet();

      final pending = _migrations
        ..sort((a, b) => a.version.compareTo(b.version));

      for (final m in pending) {
        if (appliedSet.contains(m.version)) continue;

        m.up(tx);
        db.execute(
          'INSERT INTO $migrationTable (version, applied_at) VALUES (?, CURRENT_TIMESTAMP)',
          [m.version],
        );
      }
    });
  }
}
