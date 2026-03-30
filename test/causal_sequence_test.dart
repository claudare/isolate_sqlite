import 'package:test/test.dart';
import 'package:isolate_sqlite/src/isolate_sqlite.dart';

class CausalDb extends IsolateSqlite {
  CausalDb() : super(IsolateSqlite.memoryInitFn);

  Future<void> setup() async {
    await exec('''
      CREATE TABLE event (
        device_id INTEGER NOT NULL,
        device_sequence INTEGER NOT NULL,
        causal_sequence INTEGER NOT NULL,
        local_sequence INTEGER NOT NULL,
        PRIMARY KEY (local_sequence)
      );
    ''');

    await exec(
      'CREATE INDEX idx_device_sequence ON event(device_id, device_sequence);',
    );
    await exec(
      'CREATE INDEX idx_causal_sequence ON event(device_id, causal_sequence);',
    );

    await exec('''
      CREATE VIEW next_device_sequence AS
      SELECT device_id, COALESCE(MAX(device_sequence), 0) + 1 AS next_seq
      FROM event
      GROUP BY device_id;
    ''');

    await exec('''
      CREATE VIEW next_causal_sequence AS
      SELECT device_id, COALESCE(MAX(causal_sequence), 0) + 1 AS next_seq
      FROM event
      GROUP BY device_id;
    ''');

    await exec('''
      CREATE VIEW next_local_sequence AS
      SELECT COALESCE(MAX(local_sequence), 0) + 1 AS next_seq
      FROM event;
    ''');
  }

  Future<void> insertEvent(int deviceId) => exec(
    '''
    INSERT INTO event (device_id, device_sequence, causal_sequence, local_sequence)
    VALUES (
      ?,
      COALESCE((SELECT next_seq FROM next_device_sequence WHERE device_id = ?), 1),
      COALESCE((SELECT next_seq FROM next_causal_sequence WHERE device_id = ?), 1),
      (SELECT next_seq FROM next_local_sequence)
    );
  ''',
    [deviceId, deviceId, deviceId],
  );

  Future<List<int>> deviceSequences(int deviceId) async {
    final rows = await query(
      'SELECT device_sequence FROM event WHERE device_id = ? ORDER BY device_sequence',
      [deviceId],
    );
    return [for (final r in rows) r[0] as int];
  }

  Future<List<int>> causalSequences(int deviceId) async {
    final rows = await query(
      'SELECT causal_sequence FROM event WHERE device_id = ? ORDER BY causal_sequence',
      [deviceId],
    );
    return [for (final r in rows) r[0] as int];
  }

  Future<List<int>> localSequences() async {
    final rows = await query(
      'SELECT local_sequence FROM event ORDER BY local_sequence',
    );
    return [for (final r in rows) r[0] as int];
  }
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

  test('device_sequence increments per device', () async {
    await db.insertEvent(1); // 1
    await db.insertEvent(1); // 2
    await db.insertEvent(2); // 1

    expect(await db.deviceSequences(1), [1, 2]);
    expect(await db.deviceSequences(2), [1]);
  });

  test('causal_sequence increments per device', () async {
    await db.insertEvent(1); // 1
    await db.insertEvent(1); // 2
    await db.insertEvent(2); // 1

    expect(await db.causalSequences(1), [1, 2]);
    expect(await db.causalSequences(2), [1]);
  });

  test('local_sequence increments globally', () async {
    await db.insertEvent(1); // 1
    await db.insertEvent(1); // 2
    await db.insertEvent(2); // 3

    expect(await db.localSequences(), [1, 2, 3]);
  });

  test('failed insert does not consume sequences', () async {
    await db.insertEvent(1); // local 1, device 1, causal 1
    await db.insertEvent(1); // local 2, device 2, causal 2

    expect(
      () => db.exec(
        'INSERT INTO event (device_id, device_sequence, causal_sequence, local_sequence) VALUES (NULL, 1, 1, 99)',
      ),
      throwsException,
    );

    await db.insertEvent(1); // local 3, device 3, causal 3
    expect(await db.deviceSequences(1), [1, 2, 3]);
    expect(await db.causalSequences(1), [1, 2, 3]);
    expect(await db.localSequences(), [1, 2, 3]);
  });

  test('primary key is local_sequence', () async {
    await db.insertEvent(1); // local 1

    expect(
      () => db.exec(
        'INSERT INTO event (device_id, device_sequence, causal_sequence, local_sequence) VALUES (?, ?, ?, ?)',
        [1, 99, 99, 1],
      ),
      throwsException,
    );
  });
}
