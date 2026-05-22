import 'dart:async';
import 'dart:isolate';
import 'package:sqlite3/sqlite3.dart' show Database, OpenMode, sqlite3;

import 'execute_result.dart';
import 'row.dart';
import 'rows.dart';
import 'sync_context.dart';

const _memoryFilename = ':memory:';

typedef SetupFn = void Function(Database);

class IsolateSqlite {
  bool _isOpen = false;
  late final SendPort _cmdPort;
  late final Isolate _isolate;

  IsolateSqlite();

  /// Opens a database file.
  ///
  /// The [vfs] option can be used to set the appropriate virtual file system
  /// implementation. When null, the default file system will be used.
  ///
  /// If [uri] is enabled (defaults to `false`), the [filename] will be
  /// interpreted as an uri as according to https://www.sqlite.org/uri.html.
  ///
  /// If the [mutex] parameter is set to true, the `SQLITE_OPEN_FULLMUTEX` flag
  /// will be set. If it's set to false, `SQLITE_OPEN_NOMUTEX` will be enabled.
  /// By default, neither parameter will be set.
  Future<void> open(
    String filename, {
    String? vfs,
    OpenMode mode = OpenMode.readWriteCreate,
    bool uri = false,
    bool? mutex,
    SetupFn? setup,
  }) async {
    if (_isOpen) {
      throw StateError('Database already opened');
    }
    _isOpen = true;

    final options = _OpenOptions(
      filename: filename,
      vfs: vfs,
      mode: mode,
      uri: uri,
      mutex: mutex,
      setup: setup,
    );

    final rp = ReceivePort();
    _isolate = await Isolate.spawn(_isolateMain, (options, rp.sendPort));
    _cmdPort = await rp.first as SendPort;
  }

  /// Opens an in-memory database.
  ///
  /// The [vfs] option can be used to set the appropriate virtual file system
  /// implementation. When null, the default file system will be used.
  Future<void> openInMemory({String? vfs, SetupFn? setup}) {
    return open(_memoryFilename, vfs: vfs, setup: setup);
  }

  static FutureOr<void> _isolateMain((_OpenOptions, SendPort) args) async {
    final (options, initPort) = args;

    final db = options.filename == _memoryFilename
        ? sqlite3.openInMemory(vfs: options.vfs)
        : sqlite3.open(
            options.filename,
            vfs: options.vfs,
            mode: options.mode,
            uri: options.uri,
            mutex: options.mutex,
          );

    if (options.setup != null) {
      options.setup!(db);
    }

    final cmdPort = ReceivePort();
    initPort.send(cmdPort.sendPort);

    cmdPort.listen((message) {
      final msg = message as List;
      final type = msg[0] as _IsolateSendType;
      final replyTo = msg[1] as SendPort;

      switch (type) {
        // ── Run: ['run', callback, replyTo]
        case _IsolateSendType.run:
          final fn = msg[2] as Object? Function(SyncContext);
          final ctx = SyncContext(db, isDatabaseTransaction: false);

          try {
            final result = fn(ctx);
            replyTo.send([null, result]);
          } catch (e, st) {
            replyTo.send([_IsolateError(e, st), null]);
          }
          return;
        case _IsolateSendType.transaction:
          final fn = msg[2] as Object? Function(SyncContext);
          final ctx = SyncContext(db, isDatabaseTransaction: true);

          try {
            db.execute('BEGIN');
            final result = fn(ctx);
            db.execute('COMMIT');
            replyTo.send([null, result]);
          } catch (e, st) {
            try {
              db.execute('ROLLBACK');
            } catch (_) {}
            replyTo.send([_IsolateError(e, st), null]);
          }
          return;
        case _IsolateSendType.close:
          try {
            db.close();

            replyTo.send([null, null]);
          } catch (e, st) {
            replyTo.send([_IsolateError(e, st), null]);
          } finally {
            cmdPort.close();
          }
      }
    });
  }

  Future<T> _runInIsolate<T>(_IsolateSendType type, Object? arg) async {
    final rp = ReceivePort();
    _cmdPort.send([type, rp.sendPort, arg]);
    final resp = await rp.first as List;
    rp.close();
    if (resp[0] != null) {
      (resp[0] as _IsolateError).throwError();
    }

    return resp[1] as T;
  }

  /// Runs the synchronous [action] in the isolate and returns the result.
  /// This method does not issue BEGIN/COMMIT transactions, unlike [transaction].
  /// Any errors thrown by the function are rethrown.
  Future<T> run<T>(T Function(SyncContext ctx) action) async {
    if (!_isOpen) throw StateError('IsolateSqlite is not opened');

    return _runInIsolate(_IsolateSendType.run, action);
  }

  /// Runs the synchronous [action] inside the sqlite transaction and returns the result.
  /// Execution of action is wrapped in a BEGIN/COMMIT transaction.
  /// Any errors thrown by the function issues a ROLLBACK before rethrowing.
  Future<T> transaction<T>(T Function(SyncContext tx) action) async {
    if (!_isOpen) throw StateError('IsolateSqlite is not opened');

    return _runInIsolate(_IsolateSendType.transaction, action);
  }

  Future<void> close() async {
    if (!_isOpen) return;

    try {
      await _runInIsolate(_IsolateSendType.close, null);
    } catch (e, st) {
      // TODO: should close error be ignored?
      Error.throwWithStackTrace(e, st);
    } finally {
      _isolate.kill(priority: Isolate.immediate);
      _isOpen = false;
    }
  }

  /// Queries and returns all rows.
  /// Throws [SqliteException] if sqlite error occurs.
  Future<Rows> query(String sql, [List<Object?> params = const []]) {
    return run((tx) => tx.query(sql, params));
  }

  /// Queries and returns the first row, `null` if no rows are returned.
  /// Throws [SqliteException] if sqlite error occurs.
  Future<Row?> queryRow(String sql, [List<Object?> params = const []]) {
    return run((tx) => tx.queryRow(sql, params));
  }

  /// Queries and returns the first value of the first row.
  /// Throws [StateError] if more then one row is returned or if nullability is
  /// incompatible with [T].
  /// Throws [SqliteException] if sqlite error occurs.
  Future<T> queryValue<T>(String sql, [List<Object?> params = const []]) {
    return run((tx) => tx.queryValue<T>(sql, params));
  }

  /// Executes SQL and returns nothing.
  /// Throws [SqliteException] if sqlite error occurs.
  Future<ExecuteResult> execute(String sql, [List<Object?> params = const []]) {
    return run((tx) => tx.execute(sql, params));
  }

  // all-in-one best practices pragma settings
  // TODO: move me out somewhere else
  static void enableOptimizations(Database db) {
    db.execute('PRAGMA journal_mode=WAL;');
    db.execute('PRAGMA busy_timeout = 1000;');
  }
}

class _OpenOptions {
  String filename;
  String? vfs;
  OpenMode mode;
  bool uri = false;
  bool? mutex;
  SetupFn? setup;

  _OpenOptions({
    required this.filename,
    this.vfs,
    this.mode = OpenMode.readWriteCreate,
    this.uri = false,
    this.mutex,
    this.setup,
  });
}

enum _IsolateSendType { run, transaction, close }

class _IsolateError {
  final Object _error;
  final String _stackTraceString;

  _IsolateError(this._error, StackTrace stackTrace)
    : _stackTraceString = stackTrace.toString();

  /// Throws the original error. Call on the receiving side.
  Never throwError() => Error.throwWithStackTrace(
    _error,
    StackTrace.fromString(_stackTraceString.toString()),
  );
}
