import 'dart:async';
import 'dart:isolate';
import 'package:meta/meta.dart';
import 'package:sqlite3/sqlite3.dart';

const dbMemoryPath = ':memory:';

typedef IsolateInitFn = void Function(Database db);

abstract class IsolateSqlite {
  final String _dbPath;
  bool _opened = false;
  late final SendPort _cmdPort;
  late final Isolate _isolate;

  IsolateSqlite(this._dbPath);

  IsolateSqlite.memory() : _dbPath = dbMemoryPath;

  /// Override to run initialization inside the background isolate.
  ///
  /// This is where you create mutable state and register custom SQL functions.
  /// Everything the closure references is created/lives in the isolate.
  ///
  /// **Copy needed fields to local variables to avoid capturing `this`.**
  @protected
  IsolateInitFn? get onIsolateInit => null;

  Future<void> open() async {
    assert(!_opened, 'Database already opened');
    _opened = true;
    final rp = ReceivePort();
    _isolate = await Isolate.spawn(_isolateMain, (
      _dbPath,
      onIsolateInit,
      rp.sendPort,
    ));
    _cmdPort = await rp.first as SendPort;
  }

  // ── Isolate entry point ──────────────────────────────────────────

  static void _isolateMain((String, IsolateInitFn?, SendPort) args) {
    final (dbPath, initFn, initPort) = args;

    final db = dbPath == dbMemoryPath
        ? sqlite3.openInMemory()
        : sqlite3.open(dbPath);

    initFn?.call(db);

    final cmdPort = ReceivePort();
    initPort.send(cmdPort.sendPort);

    cmdPort.listen((message) {
      final msg = message as List;
      final type = msg[0] as String;
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
        replyTo.send([e.toString(), null]);
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
    if (resp[0] != null) throw Exception(resp[0] as String);
    return resp[1];
  }

  // ── Protected API for subclasses ─────────────────────────────────

  @protected
  Future<List<List<Object?>>> select(
    String sql, [
    List<Object?> params = const [],
  ]) async {
    final data = await _send('select', sql, params);
    return data! as List<List<Object?>>;
  }

  @protected
  Future<List<Object?>?> selectOne(
    String sql, [
    List<Object?> params = const [],
  ]) async {
    final rows = await select(sql, params);
    return rows.isEmpty ? null : rows[0];
  }

  @protected
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

  @protected
  Future<void> execute(String sql, [List<Object?> params = const []]) async {
    await _send('execute', sql, params);
  }

  Future<void> close() async {
    await _send('close');
    _isolate.kill(priority: Isolate.immediate);
    _opened = false;
  }

  @protected
  Future<void> enableOptimizations() async {
    await execute('PRAGMA journal_mode=WAL;');
    await execute('PRAGMA busy_timeout = 1000;');
  }
}
