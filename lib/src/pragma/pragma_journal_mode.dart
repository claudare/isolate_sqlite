import 'package:isolate_sqlite/src/sync_context.dart';

import 'interfaces.dart';

enum PragmaJournalModeValue { delete, truncate, persist, memory, wal, off }

class PragmaJournalMode implements QueryOrChange<PragmaJournalModeValue> {
  final SyncContext _tx;

  const PragmaJournalMode(this._tx);

  @override
  PragmaJournalModeValue query() {
    final raw = _tx.queryValue<String>('PRAGMA journal_mode;');
    return PragmaJournalModeValue.values.byName(raw);
  }

  @override
  void change(PragmaJournalModeValue value) {
    // SQLite returns the resulting mode — it may differ from requested
    // (e.g. WAL is unsupported on some filesystems)
    final result = _tx.queryValue<String>(
      'PRAGMA journal_mode = ${value.name};',
    );
    if (result != value.name) {
      throw StateError(
        'Failed to set journal_mode to ${value.name}, got $result',
      );
    }
  }
}
