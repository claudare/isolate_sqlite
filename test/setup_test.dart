import 'dart:io';

import 'package:test/test.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';

// custom counter with side-effect
class IdGen {
  int _counter = 0;

  IdGen(this._counter);

  String nextId() {
    return '${_counter++}';
  }
}

void main() {
  late IsolateSqlite db;
  // late InitRepo repo;

  setUp(() async {
    db = IsolateSqlite();
    await db.openInMemory(
      setup: (db) {
        IsolateSqlite.enableOptimizations(db);

        // This entire block runs inside the isolate.
        // Sideeffect classes are BORN here and they LIVE here.
        final idGen = IdGen(100);

        db.createFunction(
          functionName: 'next_id',
          argumentCount: const AllowedArgumentCount(0),
          function: (_) => idGen.nextId(),
        );
        db.createFunction(
          functionName: 'double_it',
          argumentCount: const AllowedArgumentCount(1),
          function: (args) => (args[0] as int) * 2,
        );
        db.createFunction(
          functionName: 'is_ios',
          argumentCount: const AllowedArgumentCount(0),
          function: (_) => Platform.isIOS, // NEVER!
        );
      },
    );
  });

  tearDown(() async {
    await db.close();
  });

  group("onIsolateInit", () {
    test("side-effects work across isolate boundaries", () async {
      expect(await db.queryValue('SELECT next_id()'), "100");
      expect(await db.queryValue('SELECT next_id()'), "101");
      expect(await db.queryValue('SELECT next_id()'), "102");
    });

    test("can use arguments", () async {
      expect(await db.queryValue('SELECT double_it(42)'), 84);
    });

    test("can access sideeffects", () async {
      expect(await db.queryValue('SELECT is_ios()'), 0);
    });
  });
}
