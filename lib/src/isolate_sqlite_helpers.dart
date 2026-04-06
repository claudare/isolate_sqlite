import 'dart:io';
import 'dart:math';

class IsolateSqliteHelpers {
  static void deleteDatabaseFiles(String path) {
    for (final suffix in ['', '-wal', '-shm']) {
      final f = File('$path$suffix');
      if (f.existsSync()) f.deleteSync();
    }
  }

  static String tempDbPath() {
    final id = _randomHex(16);
    final dir = Directory.systemTemp.path;
    return '$dir/isolate_sqlite_$id.db';
  }

  static String _randomHex(int bytes) {
    final rng = Random.secure();

    return List.generate(
      bytes,
      (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }
}
