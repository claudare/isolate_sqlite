import 'package:sqlite3/sqlite3.dart' show Database;

import 'interfaces.dart';

// enum PragmaJournalModeValue { delete, truncate, persist, memory, wal, off }

// class PragmaJournalMode implements QueryOrChange<PragmaJournalModeValue> {
//   final Database _db;

//   const PragmaJournalMode(this._db);

//   @override
//   PragmaJournalModeValue query() {
//     // properly convert to strings
//     return PragmaJournalModeValue.wal;
//   }

//   @override
//   void change(PragmaJournalModeValue value) {}
// }
