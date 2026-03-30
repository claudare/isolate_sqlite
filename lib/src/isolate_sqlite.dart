import 'dart:async';
import 'dart:isolate';
import 'package:isolate_sqlite/src/solate_sqlite_exception.dart';
import 'package:sqlite3/sqlite3.dart';

typedef IsolateInitFn = Database Function();
// typedef IsolateConfigFn = void Function(Database);

class Transaction {
  final Database _db;
  Transaction._(this._db);

  List<List<Object?>> select(String sql, [List<Object?> params = const []]) {
    return _db.select(sql, params).rows;
  }

  List<Object?>? selectOne(String sql, [List<Object?> params = const []]) {
    final rows = select(sql, params);
    return rows.isEmpty ? null : rows[0];
  }

  T? selectValue<T extends Object>(
    String sql, [
    List<Object?> params = const [],
  ]) {
    final rows = select(sql, params);
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

// ── Base class ─────────────────────────────────────────────────────

class IsolateSqlite {
  bool _opened = false;
  final IsolateInitFn _initFn;
  late final SendPort _cmdPort;
  late final Isolate _isolate;

  IsolateSqlite(this._initFn);

  static IsolateInitFn memoryInitFn = () => sqlite3.openInMemory();

  // IsolateConfigFn? get onIsolateInit => null;

  Future<void> open() async {
    assert(!_opened, 'Database already opened');
    _opened = true;
    final rp = ReceivePort();
    _isolate = await Isolate.spawn(_isolateMain, (_initFn, rp.sendPort));
    _cmdPort = await rp.first as SendPort;
  }

  // ── Isolate entry point ──────────────────────────────────────────

  static List _serializeError(Object e) {
    if (e is SqliteException) {
      return ['sqlite', e.message, e.extendedResultCode, e.explanation];
    }
    return ['generic', e.toString(), null, null];
  }

  static Exception _deserializeError(List err) {
    final kind = err[0] as String;
    if (kind == 'sqlite') {
      return IsolateSqliteException(
        err[1] as String,
        sqliteResultCode: err[2] as int?,
        explanation: err[3] as String?,
      );
    }
    return Exception(err[1] as String);
  }

  static void _isolateMain((IsolateInitFn, SendPort) args) {
    final (initFn, initPort) = args;

    final db = initFn();

    final cmdPort = ReceivePort();
    initPort.send(cmdPort.sendPort);

    cmdPort.listen((message) {
      final msg = message as List;
      final type = msg[0] as String;

      // ── Transaction: ['transaction', callback, replyTo]
      if (type == 'transaction') {
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
          case 'select':
            final rs = db.select(sql, params);
            replyTo.send([null, rs.rows]);
          case 'execute':
            db.execute(sql, params);
            replyTo.send([null, null]);
          case 'close':
            db.close();
            replyTo.send([null, null]);
            cmdPort.close();
        }
      } catch (e) {
        replyTo.send([_serializeError(e), null]);
      }
    });
  }

  // ── Internal messaging ───────────────────────────────────────────

  Future<Object?> _send(
    String type, [
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

  // ── Protected API for subclasses ─────────────────────────────────

  Future<List<List<Object?>>> select(
    String sql, [
    List<Object?> params = const [],
  ]) async {
    final data = await _send('select', sql, params);
    return data! as List<List<Object?>>;
  }

  Future<List<Object?>?> selectOne(
    String sql, [
    List<Object?> params = const [],
  ]) async {
    final rows = await select(sql, params);
    return rows.isEmpty ? null : rows[0];
  }

  Future<T?> selectValue<T extends Object>(
    String sql, [
    List<Object?> params = const [],
  ]) async {
    final rows = await select(sql, params);
    return rows.isEmpty
        ? null
        : rows[0].isEmpty
        ? null
        : rows[0][0] as T;
  }

  Future<void> execute(String sql, [List<Object?> params = const []]) async {
    await _send('execute', sql, params);
  }

  Future<T> transaction<T>(T Function(Transaction tx) action) async {
    final rp = ReceivePort();
    _cmdPort.send(['transaction', action, rp.sendPort]);
    final resp = await rp.first as List;
    rp.close();
    if (resp[0] != null) throw _deserializeError(resp[0] as List);
    return resp[1] as T;
  }

  Future<void> close() async {
    await _send('close');
    _isolate.kill(priority: Isolate.immediate);
    _opened = false;
  }

  static void enableOptimizations(Database db) {
    db.execute('PRAGMA journal_mode=WAL;');
    db.execute('PRAGMA busy_timeout = 1000;');
  }
}
