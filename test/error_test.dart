import 'package:isolate_sqlite/isolate_sqlite.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

class ErrorRepo extends IsolateSqlite {
  ErrorRepo(super.initFn);

  Future<void> createTable() =>
      exec('CREATE TABLE t (id TEXT PRIMARY KEY, val TEXT NOT NULL)');

  Future<void> insert(String id, String val) =>
      exec('INSERT INTO t (id, val) VALUES (?, ?)', [id, val]);

  Future<void> badSql() => exec('NOT VALID SQL');

  Future<void> badTransaction() => transaction((tx) {
    tx.exec('NOT VALID SQL');
  });

  Future<void> dartException() => transaction((tx) {
    throw Exception('dart exception');
  });

  Future<void> dartError() => transaction((tx) {
    throw Error();
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
    test('SqliteException is returned in full', () async {
      await repo.insert('1', 'first');

      try {
        await repo.insert('1', 'dupe');
        fail('should have thrown');
      } on SqliteException catch (e) {
        expect(e.message, "UNIQUE constraint failed: t.id");
        expect(e.explanation, "constraint failed (code 1555)");
        expect(
          e.extendedResultCode,
          SqlExtendedError.SQLITE_CONSTRAINT_PRIMARYKEY,
        );
        expect(e.resultCode, 19);
        expect(e.offset, isNull);
        expect(e.operation, "executing statement");
        expect(e.causingStatement, "INSERT INTO t (id, val) VALUES (?, ?)");
        expect(e.parametersToStatement, equals(['1', 'dupe']));
      }
    });

    test('bad SQL throws SqliteException', () async {
      expect(() => repo.badSql(), throwsA(isA<SqliteException>()));
    });

    test('duplicate primary key throws SqliteException', () async {
      await repo.insert('1', 'first');

      expect(() => repo.insert('1', 'dupe'), throwsA(isA<SqliteException>()));
    });

    test('bad SQL in transaction throws SqliteException', () async {
      expect(() => repo.badTransaction(), throwsA(isA<SqliteException>()));
    });

    test('dart exception passthrough', () async {
      expect(
        () => repo.dartException(),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'msg',
            contains('dart exception'),
          ),
        ),
      );
    });

    test('dart errors are passed through', () async {
      expect(() => repo.dartError(), throwsA(isA<Error>()));
    });
  });
}
