import 'package:sqlite3/sqlite3.dart' show Database;

import 'interfaces.dart';

// TODO: schema?
class PragmaForeignKeys implements QueryOrChange<bool> {
  final Database _db;

  const PragmaForeignKeys(this._db);

  @override
  bool query() {
    final raw = _db.select('PRAGMA foreign_keys;');
    // print("RAW QUERY: $raw, first first: ${raw.rows.first.first}");

    return raw.rows.first.first == 1;
  }

  @override
  void change(bool value) {
    _db.execute('PRAGMA foreign_keys = ${value ? 1 : 0};');
  }
}
