import 'package:isolate_sqlite/isolate_sqlite.dart';
import 'package:test/test.dart';

void main() {
  late IsolateSqlite iso;

  setUp(() async {
    iso = IsolateSqlite(() => sqlite3.openInMemory());
    await iso.open();
    await iso.execute("CREATE TABLE test (id TEXT PRIMARY KEY);");
  });

  tearDown(() async {
    await iso.close();
  });

  // stack traces are shown
  // test('stack traces are reported', () async {
  //   await iso.transaction((db) {
  //     // empty line
  //     db.exec("INSERT INTO BAD SYNTAX (id) VALUES ()");
  //     // stack trace checking
  //   });
  // });
}
