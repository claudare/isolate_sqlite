import 'package:test/test.dart';
import 'package:isolate_sqlite/src/isolate_sqlite.dart';

class TxRepo extends IsolateSqlite {
  TxRepo(super.initFn);

  Future<void> createTable() => execute('''
    CREATE TABLE account (
      id TEXT PRIMARY KEY,
      balance INTEGER NOT NULL CHECK(balance >= 0)
    )
  ''');

  Future<void> seed(String id, int balance) =>
      execute('INSERT INTO account (id, balance) VALUES (?, ?)', [id, balance]);

  Future<int?> balanceOf(String id) =>
      selectValue<int>('SELECT balance FROM account WHERE id = ?', [id]);

  Future<({int from, int to})> transfer(String from, String to, int amount) =>
      transaction((tx) {
        tx.execute('UPDATE account SET balance = balance - ? WHERE id = ?', [
          amount,
          from,
        ]);
        tx.execute('UPDATE account SET balance = balance + ? WHERE id = ?', [
          amount,
          to,
        ]);

        final fromBal = tx.selectValue<int>(
          'SELECT balance FROM account WHERE id = ?',
          [from],
        )!;
        final toBal = tx.selectValue<int>(
          'SELECT balance FROM account WHERE id = ?',
          [to],
        )!;

        return (from: fromBal, to: toBal);
      });

  Future<void> failMidway(String id) => transaction((tx) {
    tx.execute('UPDATE account SET balance = 999 WHERE id = ?', [id]);
    throw Exception('deliberate');
  });
}

void main() {
  late TxRepo repo;

  setUp(() async {
    repo = TxRepo(IsolateSqlite.memoryInitFn);
    await repo.open();
    await repo.createTable();
    await repo.seed('alice', 100);
    await repo.seed('bob', 50);
  });

  tearDown(() => repo.close());

  test('commits and returns result', () async {
    final r = await repo.transfer('alice', 'bob', 30);

    expect(r, (from: 70, to: 80));
    expect(await repo.balanceOf('alice'), 70);
    expect(await repo.balanceOf('bob'), 80);
  });

  test('rolls back on dart exception', () async {
    expect(() => repo.failMidway('alice'), throwsException);

    expect(await repo.balanceOf('alice'), 100);
  });

  test('rolls back on constraint violation', () async {
    expect(() => repo.transfer('bob', 'alice', 999), throwsException);

    expect(await repo.balanceOf('alice'), 100);
    expect(await repo.balanceOf('bob'), 50);
  });

  test('db works after rollback', () async {
    expect(() => repo.failMidway('alice'), throwsException);

    final r = await repo.transfer('alice', 'bob', 10);
    expect(r, (from: 90, to: 60));
  });
}
