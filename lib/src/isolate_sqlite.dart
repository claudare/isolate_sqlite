import 'dart:async';
import 'dart:isolate';
import 'package:isolate_sqlite/src/isolate_error.dart';
import 'package:sqlite3/sqlite3.dart';

typedef SetupFn = void Function(Database);

const _memoryFilename = ':memory:';

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

enum _IsolateSendType { transaction, select, execute, close }

// TODO: docs
class Transaction {
  final Database _db;
  const Transaction._(this._db);

  List<List<Object?>> query(String sql, [List<Object?> params = const []]) {
    return _db.select(sql, params).rows;
  }

  List<Object?>? queryRow(String sql, [List<Object?> params = const []]) {
    final rows = query(sql, params);
    if (rows.length > 1) {
      throw StateError('More than one row returned for queryRow');
    }

    return rows.isEmpty ? null : rows[0];
  }

  T? queryValue<T extends Object>(
    String sql, [
    List<Object?> params = const [],
  ]) {
    final rows = query(sql, params);
    if (rows.length > 1) {
      throw StateError('More than one row returned for queryValue');
    }

    return rows.isEmpty
        ? null
        : rows[0].isEmpty
        ? null
        : rows[0][0] as T;
  }

  void execute(String sql, [List<Object?> params = const []]) {
    _db.execute(sql, params);
  }
}

class IsolateSqlite {
  bool _opened = false;
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
    if (_opened) {
      throw StateError('Database already opened');
    }
    _opened = true;

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

      // ── Transaction: ['transaction', callback, replyTo]
      if (type == _IsolateSendType.transaction) {
        final fn = msg[1] as Object? Function(Transaction);
        final replyTo = msg[2] as SendPort;

        try {
          db.execute('BEGIN');
          final result = fn(Transaction._(db));
          db.execute('COMMIT');
          replyTo.send([null, result]);
        } catch (e, st) {
          try {
            db.execute('ROLLBACK');
          } catch (_) {}
          replyTo.send([IsolateError(e, st), null]);
        }
        return;
      }

      // ── Standard: ['type', sql, params, replyTo]
      final sql = msg[1] as String;
      final params = (msg[2] as List).cast<Object?>();
      final replyTo = msg[3] as SendPort;

      try {
        switch (type) {
          case _IsolateSendType.select:
            final rs = db.select(sql, params);
            replyTo.send([null, rs.rows]);
          case _IsolateSendType.execute:
            db.execute(sql, params);
            replyTo.send([null, null]);
          case _IsolateSendType.close:
            db.close();
            replyTo.send([null, null]);
            cmdPort.close();
          default:
        }
      } catch (e, st) {
        replyTo.send([IsolateError(e, st), null]);
      }
    });
  }

  Future<Object?> _send(
    _IsolateSendType type, [
    String sql = '',
    List<Object?> params = const [],
  ]) async {
    final rp = ReceivePort();
    _cmdPort.send([type, sql, params, rp.sendPort]);
    final resp = await rp.first as List;
    rp.close();
    if (resp[0] != null) {
      (resp[0] as IsolateError).throwError();
    }

    return resp[1];
  }

  /// Queries and returns all rows.
  /// Throws [SqliteException] if sqlite error occurs.
  Future<List<List<Object?>>> query(
    String sql, [
    List<Object?> params = const [],
  ]) async {
    final data = await _send(_IsolateSendType.select, sql, params);
    return data! as List<List<Object?>>;
  }

  /// Queries and returns the first row, `null` if no rows are returned.
  /// Throws [SqliteException] if sqlite error occurs.
  Future<List<Object?>?> queryRow(
    String sql, [
    List<Object?> params = const [],
  ]) async {
    final rows = await query(sql, params);
    if (rows.length > 1) {
      throw StateError('More than one row returned for queryValue');
    }

    return rows.isEmpty ? null : rows[0];
  }

  /// Queries and returns the first value of the first row, `null` if no rows are returned.
  /// Throws [StateError] if more then one row is returned.
  /// Throws [SqliteException] if sqlite error occurs.
  Future<T?> queryValue<T extends Object>(
    String sql, [
    List<Object?> params = const [],
  ]) async {
    final rows = await query(sql, params);
    if (rows.length > 1) {
      throw StateError('More than one row returned for queryValue');
    }

    return rows.isEmpty
        ? null
        : rows[0].isEmpty
        ? null
        : rows[0][0] as T;
  }

  /// Executes SQL and returns nothing.
  /// Throws [SqliteException] if sqlite error occurs.
  Future<void> execute(String sql, [List<Object?> params = const []]) async {
    await _send(_IsolateSendType.execute, sql, params);
  }

  /// Starts a syncronous transaction.
  Future<T> transaction<T>(T Function(Transaction tx) action) async {
    final rp = ReceivePort();
    _cmdPort.send([_IsolateSendType.transaction, action, rp.sendPort]);
    final resp = await rp.first as List;
    rp.close();

    if (resp[0] != null) {
      (resp[0] as IsolateError).throwError();
    }

    return resp[1] as T;
  }

  Future<void> close() async {
    await _send(_IsolateSendType.close);
    _isolate.kill(priority: Isolate.immediate);
    _opened = false;
  }

  static void enableOptimizations(Database db) {
    db.execute('PRAGMA journal_mode=WAL;');
    db.execute('PRAGMA busy_timeout = 1000;');
  }
}
