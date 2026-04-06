import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';

// ── Tests ───────────────────────────────────────────────────────────

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

  test('insert and retrieve by id', () async {
    await iso.execute("INSERT INTO test (id) VALUES ('1')");

    final result = await iso.queryValue<String>(
      "SELECT id FROM test WHERE id = ?",
      ['1'],
    );

    expect(result, '1');
  });
}
