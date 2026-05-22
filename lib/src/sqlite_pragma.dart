import 'package:sqlite3/sqlite3.dart' show Database;

// https://sqlite.org/pragma.html

/// a typed helpers for pragmas
/// things like foreign key support, wal, and timeouts
class SqlitePragma {
  // all-in-one best practices pragma settings
  static void enableOptimizations(Database db) {
    db.execute('PRAGMA journal_mode=WAL;');
    db.execute('PRAGMA busy_timeout = 1000;');
  }
}
