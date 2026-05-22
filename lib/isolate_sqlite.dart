/// Support for doing something awesome.
///
/// More dartdocs go here.
library;

export 'src/isolate_sqlite.dart';
export 'src/sqlite_migration.dart';
export 'src/sqlite_helpers.dart';
export 'src/execute_result.dart';
export 'src/rows.dart';
export 'src/row.dart';
export 'src/sync_context.dart';

// TODO: only nessesary dependencies can be re-exported
export 'package:sqlite3/sqlite3.dart'
    show
        sqlite3,
        SqliteException,
        SqlExtendedError,
        Sqlite3,
        Database,
        AllowedArgumentCount;

// export 'package:sqlite3/sqlite3.dart';
