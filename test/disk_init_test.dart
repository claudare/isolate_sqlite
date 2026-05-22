import 'package:isolate_sqlite/isolate_sqlite.dart';
import 'package:test/test.dart';

void main() {
  group("Disk init", () {
    late IsolateSqlite db;
    late String dbPath;

    setUp(() async {
      dbPath = SqliteHelpers.tempDbPath();
      db = IsolateSqlite();
      await db.open(dbPath);
    });

    tearDown(() async {
      await db.close();
      SqliteHelpers.deleteDatabaseFiles(dbPath);
    });

    test("works", () async {
      await db.execute(
        "CREATE TABLE test (id INTEGER PRIMARY KEY, value TEXT)",
      );
      await db.execute("INSERT INTO test (value) VALUES (?)", ["hello"]);
      final result = await db.queryRow("SELECT * FROM test WHERE id = ?", [1]);
      expect(result!.values, [1, "hello"]);
    });
  });
}
