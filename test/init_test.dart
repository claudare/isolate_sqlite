import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
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

class InitRepo extends IsolateSqlite {
  InitRepo(IsolateInitFn initFn, int startSeq)
    : super(() async {
        // async is okay too
        await Future.delayed(Duration(milliseconds: 10));

        final db = await initFn();

        IsolateSqlite.enableOptimizations(db);

        // This entire block runs inside the isolate.
        // Sideeffect classes are BORN here and they LIVE here.
        final idGen = IdGen(startSeq);

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

        return db;
      });

  Future<String> nextId() async {
    final rows = await query('SELECT next_id()');
    return rows[0][0] as String;
  }

  Future<int> doubleIt(int value) async {
    final rows = await query('SELECT double_it(?)', [value]);
    return rows[0][0] as int;
  }

  Future<bool> isIos() async {
    final rows = await query('SELECT is_ios()');
    return (rows[0][0] as int) == 1;
  }
}

// ── Tests ───────────────────────────────────────────────────────────

void main() {
  late InitRepo repo;

  setUp(() async {
    repo = InitRepo(IsolateSqlite.memoryInitFn, 100);
    await repo.open();
  });

  tearDown(() async {
    await repo.close();
  });

  group("onIsolateInit", () {
    test("side-effects work across isolate boundaries", () async {
      expect(await repo.nextId(), "100");
      expect(await repo.nextId(), "101");
      expect(await repo.nextId(), "102");
    });

    test("can use arguments", () async {
      expect(await repo.doubleIt(42), 84);
    });

    test("can access fat away sideeffects", () async {
      expect(await repo.isIos(), false);
    });
  });
}
