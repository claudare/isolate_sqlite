import 'package:isolate_sqlite/src/sync_context.dart';

import 'interfaces.dart';

// TODO: schema?
class PragmaForeignKeys implements QueryOrChange<bool> {
  final SyncContext _ctx;

  const PragmaForeignKeys(this._ctx);

  @override
  bool query() {
    final raw = _ctx.db.select('PRAGMA foreign_keys;');
    // print("RAW QUERY: $raw, first first: ${raw.rows.first.first}");

    return raw.rows.first.first == 1;
  }

  @override
  void change(bool value) {
    if (_ctx.isDatabaseTransaction) {
      throw StateError('Cannot change foreign_keys in a transaction');
    }
    _ctx.db.execute('PRAGMA foreign_keys = ${value ? 1 : 0};');
  }
}
