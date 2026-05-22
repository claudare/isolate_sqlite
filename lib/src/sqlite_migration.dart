import 'package:isolate_sqlite/src/transaction.dart';

import 'isolate_sqlite.dart';

typedef MigrationFn = void Function(Transaction tx);

class SqliteMigration {
  final int version;
  final MigrationFn up;

  // TODO: make up a named paramter
  const SqliteMigration(this.version, this.up);
}

// TODO: implement "down" migrations?
// TODO: option to disable foreign key constraints?
class SqliteMigrations {
  final String _migrationTable;
  final List<SqliteMigration> _migrations = [];

  SqliteMigrations({required String migrationTable})
    : _migrationTable = migrationTable;

  void add(SqliteMigration migration) {
    _migrations.add(migration);
  }

  // TODO: increase maximum lock time on the database, as migrations could be long!
  Future<void> migrate(IsolateSqlite db) async {
    await db.transaction((tx) {
      tx.execute('''
        CREATE TABLE IF NOT EXISTS $_migrationTable (
          version INTEGER PRIMARY KEY,
          applied_at TEXT NOT NULL
        )
      ''');

      final applied = tx.query(
        'SELECT version FROM $_migrationTable ORDER BY version',
      );
      final appliedSet = applied.map((r) => r[0] as int).toSet();

      final pending = _migrations
        ..sort((a, b) => a.version.compareTo(b.version));

      for (final m in pending) {
        if (appliedSet.contains(m.version)) continue;

        m.up(tx);
        db.execute(
          'INSERT INTO $_migrationTable (version, applied_at) VALUES (?, CURRENT_TIMESTAMP)',
          [m.version],
        );
      }
    });
  }
}
