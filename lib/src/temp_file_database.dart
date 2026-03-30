import 'dart:io';
import 'dart:math';

import 'package:sqlite3/sqlite3.dart';

import 'isolate_sqlite.dart';

/// Creates a temporary database file and cleans it up on dispose.
class TempFileDatabase {
  final String path;

  TempFileDatabase._(this.path);

  /// Creates a new temp database with a random filename.
  factory TempFileDatabase() {
    final id = _randomHex(16);
    final dir = Directory.systemTemp.path;
    return TempFileDatabase._('$dir/isolate_sqlite_$id.db');
  }

  IsolateInitFn get initFn =>
      () => sqlite3.open(path);

  /// Deletes the database file and WAL/SHM sidecars.
  void dispose() {
    for (final suffix in ['', '-wal', '-shm']) {
      final f = File('$path$suffix');
      if (f.existsSync()) f.deleteSync();
    }
  }

  static String _randomHex(int bytes) {
    final rng = Random.secure();
    return List.generate(
      bytes,
      (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }
}
