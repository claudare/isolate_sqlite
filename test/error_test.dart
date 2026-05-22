import 'package:isolate_sqlite/isolate_sqlite.dart';
import 'package:test/test.dart';

class ErrorRepo {
  final IsolateSqlite db;

  ErrorRepo(this.db);

  Future<void> createTable() =>
      db.execute('CREATE TABLE t (id TEXT PRIMARY KEY, val TEXT NOT NULL)');

  Future<void> insert(String id, String val) =>
      db.execute('INSERT INTO t (id, val) VALUES (?, ?)', [id, val]);

  Future<void> badSql() => db.execute('NOT VALID SQL');

  Future<void> badTransaction() => db.transaction((tx) {
    tx.execute('NOT VALID SQL');
  });

  Future<void> dartException() => db.transaction((tx) {
    throw Exception('dart exception');
  });

  Future<void> dartError() => db.transaction((tx) {
    throw Error();
  });

  Future<void> multipleErrorRow() async {
    await insert('1', 'first');
    await insert('2', 'second');
    await db.queryRow('SELECT * FROM t');
  }

  Future<void> multipleErrorValue() async {
    await insert('1', 'first');
    await insert('2', 'second');
    await db.queryValue('SELECT id FROM t');
  }
}

void main() {
  late ErrorRepo repo;

  setUp(() async {
    repo = ErrorRepo(IsolateSqlite());
    await repo.db.openInMemory();
    await repo.createTable();
  });

  tearDown(() => repo.db.close());

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

    test('multiple row return throws StateError', () async {
      expect(() => repo.multipleErrorRow(), throwsA(isA<StateError>()));
    });

    test('multiple value return throws StateError', () async {
      expect(() => repo.multipleErrorValue(), throwsA(isA<StateError>()));
    });

    test('error catching in transcations (isolate closures dont work)', () async {
      bool caught = false;

      await repo.db.transaction((tx) {
        // since this is ran inside the isolate, outside variables cant be accessed...
        // isolates are such footguns in dart
        try {
          tx.execute('NOT VALID SQL');
        } catch (e) {
          caught = true;
          // true in local scope
          // print('caught status $caught');
        }
      });

      // this is still false
      // print("resulting status: $caught");

      expect(caught, isFalse);
    });

    test('error catching in transcations', () async {
      final success = await repo.db.transaction((tx) {
        try {
          tx.execute('NOT VALID SQL');
          return true;
        } catch (_) {
          return false;
        }
      });

      expect(success, isFalse);
    });
  });
}
