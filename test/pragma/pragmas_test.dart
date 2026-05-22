import 'dart:typed_data';

import 'package:isolate_sqlite/pragma.dart';
import 'package:test/test.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';

void main() {
  late IsolateSqlite db;

  setUp(() async {
    db = IsolateSqlite();
    await db.openInMemory();
  });

  tearDown(() async {
    await db.close();
  });

  group('foreign keys', () {
    test('default value', () async {
      final result = await db.run((tx) {
        return PragmaForeignKeys(tx.db).query();
      });
      expect(result, false);
    });
    test('set and query', () async {
      await db.run((tx) {
        PragmaForeignKeys(tx.db).change(true);
      });
      final result = await db.run((tx) {
        return PragmaForeignKeys(tx.db).query();
      });
      expect(result, true);
    });
  });
}
