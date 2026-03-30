import 'package:isolate_sqlite/isolate_sqlite.dart';
import 'package:sqlite3/sqlite3.dart' show sqlite3;
import 'package:test/test.dart';

class ErrorRepo extends IsolateSqlite {
  ErrorRepo(super.initFn);

  Future<void> createTable() =>
      execute('CREATE TABLE t (id TEXT PRIMARY KEY, val TEXT NOT NULL)');

  Future<void> insert(String id, String val) =>
      execute('INSERT INTO t (id, val) VALUES (?, ?)', [id, val]);

  Future<void> badSql() => execute('NOT VALID SQL');

  Future<void> badTransaction() => transaction((tx) {
    tx.execute('NOT VALID SQL');
  });

  Future<void> dartError() => transaction((tx) {
    throw Exception('dart exception');
  });
}

void main() {
  late ErrorRepo repo;

  setUp(() async {
    repo = ErrorRepo(() => sqlite3.openInMemory());
    await repo.open();
    await repo.createTable();
  });

  tearDown(() => repo.close());

  group("errors", () {
    test('bad SQL throws IsolateSqliteException', () async {
      expect(() => repo.badSql(), throwsA(isA<IsolateSqliteException>()));
    });

    test('duplicate primary key throws IsolateSqliteException', () async {
      await repo.insert('1', 'first');

      expect(
        () => repo.insert('1', 'dupe'),
        throwsA(isA<IsolateSqliteException>()),
      );
    });

    test('exception has result code', () async {
      await repo.insert('1', 'first');

      try {
        await repo.insert('1', 'dupe');
        fail('should have thrown');
      } on IsolateSqliteException catch (e) {
        expect(e.isPrimaryKeyViolation, true);
        expect(e.sqliteResultCode, isNotNull);
        expect(e.message, isNotEmpty);
      }
    });

    test('bad SQL in transaction throws IsolateSqliteException', () async {
      expect(
        () => repo.badTransaction(),
        throwsA(isA<IsolateSqliteException>()),
      );
    });

    test('dart exception in transaction stays as Exception', () async {
      expect(
        () => repo.dartError(),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'msg',
            contains('dart exception'),
          ),
        ),
      );
    });
  });
}
