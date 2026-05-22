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
        return PragmaForeignKeys(tx).query();
      });
      expect(result, false);
    });
    test('set and query', () async {
      await db.run((tx) {
        PragmaForeignKeys(tx).change(true);
      });
      final result = await db.run((tx) {
        return PragmaForeignKeys(tx).query();
      });
      expect(result, true);
    });
    test('refuses to set in transaction', () async {
      expect(
        db.transaction((tx) {
          PragmaForeignKeys(tx).change(true);
        }),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('journal mode', () {
    test('default value', () async {
      final result = await db.run((tx) {
        return PragmaJournalMode(tx).query();
      });
      expect(result, PragmaJournalModeValue.memory);
    });
    test('set does not work in memory', () async {
      expect(
        db.run((ctx) {
          return PragmaJournalMode(ctx).change(PragmaJournalModeValue.wal);
        }),
        throwsA(isA<StateError>()),
      );
    });
  });
}
