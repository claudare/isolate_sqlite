import 'package:test/test.dart';
import 'package:isolate_sqlite/src/isolate_sqlite.dart';

class CausalDb extends IsolateSqlite {
  CausalDb() : super(IsolateSqlite.memoryInitFn);

  Future<void> setup() async {
    await exec('''
      CREATE TABLE event (
        device_id INTEGER NOT NULL,
        causal_sequence INTEGER NOT NULL,
        PRIMARY KEY (causal_sequence, device_id)
      );
    ''');

    // "next_causal_sequence(deviceId)" as a view
    await exec('''
      CREATE VIEW next_causal_sequence AS
      SELECT device_id, COALESCE(MAX(causal_sequence), 0) + 1 AS next_seq
      FROM event
      GROUP BY device_id;
    ''');
  }

  Future<void> insertEvent(int deviceId) => exec(
    '''
    INSERT INTO event (device_id, causal_sequence)
    VALUES (
      ?,
      COALESCE(
        (SELECT next_seq FROM next_causal_sequence WHERE device_id = ?),
        1
      )
    );
  ''',
    [deviceId, deviceId],
  );

  Future<List<int>> sequencesFor(int deviceId) async {
    final rows = await query(
      'SELECT causal_sequence FROM event WHERE device_id = ? ORDER BY causal_sequence',
      [deviceId],
    );
    return [for (final r in rows) r[0] as int];
  }

  Future<int?> maxSeq(int deviceId) => queryValue<int>(
    'SELECT MAX(causal_sequence) FROM event WHERE device_id = ?',
    [deviceId],
  );
}

void main() {
  late CausalDb db;

  setUp(() async {
    db = CausalDb();
    await db.open();
    await db.setup();
  });

  tearDown(() async {
    await db.close();
  });

  test('causal_sequence auto increments per device with no gaps', () async {
    await db.insertEvent(1); // seq = 1
    await db.insertEvent(1); // seq = 2
    await db.insertEvent(2); // seq = 1 (different device)

    expect(await db.sequencesFor(1), [1, 2]);
    expect(await db.sequencesFor(2), [1]);
  });

  test('failed insert does not consume a sequence', () async {
    await db.insertEvent(1); // seq = 1
    await db.insertEvent(1); // seq = 2

    // Fail: device_id is NOT NULL
    expect(
      () => db.exec(
        'INSERT INTO event (device_id, causal_sequence) VALUES (NULL, 1)',
      ),
      throwsException,
    );

    // Should still be 3 (no gap)
    await db.insertEvent(1);
    expect(await db.sequencesFor(1), [1, 2, 3]);
  });

  test('composite primary key enforces uniqueness', () async {
    await db.insertEvent(1); // seq = 1

    // Duplicate (causal_sequence, device_id)
    expect(
      () => db.exec(
        'INSERT INTO event (device_id, causal_sequence) VALUES (?, ?)',
        [1, 1],
      ),
      throwsException,
    );
  });
}
