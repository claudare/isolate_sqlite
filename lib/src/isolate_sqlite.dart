import 'dart:async';
import 'dart:isolate';
import 'package:isolate_sqlite/src/solate_sqlite_exception.dart';
import 'package:sqlite3/sqlite3.dart';

typedef IsolateInitFn = Database Function();
// typedef IsolateConfigFn = void Function(Database);

enum _IsolateSendType { transaction, select, execute, close }

enum _IsolateErrorType { sqlite, generic }

class Transaction {
  final Database _db;
  const Transaction._(this._db);

  List<List<Object?>> query(String sql, [List<Object?> params = const []]) {
    return _db.select(sql, params).rows;
  }

  List<Object?>? queryRow(String sql, [List<Object?> params = const []]) {
    final rows = query(sql, params);
    return rows.isEmpty ? null : rows[0];
  }

  T? queryValue<T extends Object>(
    String sql, [
    List<Object?> params = const [],
  ]) {
    final rows = query(sql, params);
    return rows.isEmpty
        ? null
        : rows[0].isEmpty
        ? null
        : rows[0][0] as T;
  }

  void exec(String sql, [List<Object?> params = const []]) {
    _db.execute(sql, params);
  }
}

class IsolateSqlite {
  bool _opened = false;
  final IsolateInitFn _initFn;
  late final SendPort _cmdPort;
  late final Isolate _isolate;

  IsolateSqlite(this._initFn);

  static IsolateInitFn memoryInitFn = () => sqlite3.openInMemory();

  static IsolateInitFn fileInitFn(String filename) {
    return () => sqlite3.open(filename);
  }

  Future<void> open() async {
    if (_opened) {
      throw StateError('Database already opened');
    }
    _opened = true;
    final rp = ReceivePort();
    _isolate = await Isolate.spawn(_isolateMain, (_initFn, rp.sendPort));
    _cmdPort = await rp.first as SendPort;
  }

  static List _serializeError(Object e) {
    // TODO: serialize all values as SqliteException
    if (e is SqliteException) {
      return [
        _IsolateErrorType.sqlite,
        e.message,
        e.extendedResultCode,
        e.explanation,
      ];
    }
    return [_IsolateErrorType.generic, e.toString(), null, null];
  }

  static Exception _deserializeError(List err) {
    final kind = err[0] as _IsolateErrorType;

    switch (kind) {
      case _IsolateErrorType.sqlite:
        return IsolateSqliteException(
          err[1] as String,
          sqliteResultCode: err[2] as int?,
          explanation: err[3] as String?,
        );
      case _IsolateErrorType.generic:
        return Exception(err[1] as String);
    }
  }

  static void _isolateMain((IsolateInitFn, SendPort) args) {
    final (initFn, initPort) = args;

    final db = initFn();

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
        } catch (e) {
          try {
            db.execute('ROLLBACK');
          } catch (_) {}
          replyTo.send([_serializeError(e), null]);
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
      } catch (e) {
        replyTo.send([_serializeError(e), null]);
      }
    });
  }

  // ── Internal messaging ───────────────────────────────────────────

  Future<Object?> _send(
    _IsolateSendType type, [
    String sql = '',
    List<Object?> params = const [],
  ]) async {
    final rp = ReceivePort();
    _cmdPort.send([type, sql, params, rp.sendPort]);
    final resp = await rp.first as List;
    rp.close();
    if (resp[0] != null) throw _deserializeError(resp[0] as List);
    return resp[1];
  }

  /// Queries and returns all rows.
  Future<List<List<Object?>>> query(
    String sql, [
    List<Object?> params = const [],
  ]) async {
    final data = await _send(_IsolateSendType.select, sql, params);
    return data! as List<List<Object?>>;
  }

  /// Queries and returns the first row, `null` if no rows are returned.
  Future<List<Object?>?> queryRow(
    String sql, [
    List<Object?> params = const [],
  ]) async {
    final rows = await query(sql, params);
    return rows.isEmpty ? null : rows[0];
  }

  /// Queries and returns the first value of the first row, `null` if no rows are returned.
  /// Throws [StateError] if more then one row is returned.
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
  Future<void> exec(String sql, [List<Object?> params = const []]) async {
    await _send(_IsolateSendType.execute, sql, params);
  }

  /// Starts a syncronous transaction.
  Future<T> transaction<T>(T Function(Transaction tx) action) async {
    final rp = ReceivePort();
    _cmdPort.send([_IsolateSendType.transaction, action, rp.sendPort]);
    final resp = await rp.first as List;
    rp.close();
    if (resp[0] != null) throw _deserializeError(resp[0] as List);
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
