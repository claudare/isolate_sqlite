import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';

void main() {
  late IsolateSqlite db;

  setUp(() async {
    db = IsolateSqlite(() => sqlite3.openInMemory());
    await db.open();
    await db.execute(
      "CREATE TABLE test (text TEXT PRIMARY KEY NOT NULL, integer INTEGER NOT NULL, real REAL NOT NULL, blob BLOB NOT NULL, nullable INTEGER);",
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('insert and get', () async {
    final blob = Uint8List.fromList([1, 2, 3]);

    await db.execute(
      "INSERT INTO test (text, integer, real, blob, nullable) VALUES (?, ?, ?, ?, ?)",
      ['sqlite', 2, 3.0, blob, null],
    );

    final result = await db.queryRow("SELECT * FROM test WHERE text = ?", [
      'sqlite',
    ]);

    expect(result![0], 'sqlite');
    expect(result[1], 2);
    expect(result[2], 3.0);
    expect(result[3], equals(blob));
    expect(result[4], null);
  });
}
