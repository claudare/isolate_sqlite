import 'package:isolate_sqlite/isolate_sqlite.dart';
import 'package:test/test.dart';

void main() {
  group("Disk init", () {
    late IsolateSqlite db;
    late TempFileDatabase tmp;

    setUp(() async {
      tmp = TempFileDatabase();
      db = IsolateSqlite(tmp.initFn);
      await db.open();
    });

    tearDown(() async {
      await db.close();
      tmp.dispose();
    });

    test("works", () async {
      await db.exec("CREATE TABLE test (id INTEGER PRIMARY KEY, value TEXT)");
      await db.exec("INSERT INTO test (value) VALUES (?)", ["hello"]);
      final result = await db.queryRow("SELECT * FROM test WHERE id = ?", [1]);
      expect(result, [1, "hello"]);
    });
  });
}
