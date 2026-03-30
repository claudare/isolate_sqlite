import 'dart:async';
import 'dart:isolate';
import 'package:meta/meta.dart';
import 'package:sqlite3/sqlite3.dart';

const dbMemoryPath = ':memory:';

abstract class IsolateSqlite {
  final String _dbPath;
  late final SendPort _cmdPort;
  late final Isolate _isolate;

  IsolateSqlite(this._dbPath);

  IsolateSqlite.memory() : _dbPath = dbMemoryPath;

  /// Opens the database in a background isolate.
  Future<void> open() async {
    final rp = ReceivePort();
    _isolate = await Isolate.spawn(_isolateMain, (_dbPath, rp.sendPort));
    _cmdPort = await rp.first as SendPort;
  }

  // ── Isolate entry point ──────────────────────────────────────────

  static void _isolateMain((String, SendPort) args) {
    final (dbPath, initPort) = args;

    final db = dbPath == dbMemoryPath
        ? sqlite3.openInMemory()
        : sqlite3.open(dbPath);
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
            final rows = rs.rows;

            replyTo.send([null, rows]);
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
    final casted = (data! as List).cast<List<Object?>>();

    return casted;
  }

  @protected
  Future<void> execute(String sql, [List<Object?> params = const []]) async {
    await _send('execute', sql, params);
  }

  /// Closes the database and kills the isolate.
  Future<void> close() async {
    await _send('close');
    _isolate.kill(priority: Isolate.immediate);
  }

  // other helpers
  @protected
  Future<void> enableOptimizations() async {
    // enable WAL
    await execute('PRAGMA journal_mode=WAL;');
    // wait up to 1s before SQLITE_BUSY
    await execute('PRAGMA busy_timeout = 1000;');
  }
}
