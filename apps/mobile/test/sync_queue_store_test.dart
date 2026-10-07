import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:splitcrew_mobile/src/sync_queue_store.dart';
import 'package:splitcrew_sync_protocol/splitcrew_sync_protocol.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String databasePath;

  SyncOperation operation(String id, {String tripId = 'trip-1'}) => SyncOperation(
        operationId: id,
        tripId: tripId,
        actorMemberId: 'member-1',
        expectedTripRevision: 4,
        type: SyncOperationType.createExpense,
        payload: const {
          'title': 'Dinner',
          'totalMinor': 120000,
        },
        createdAtEpochMs: 1000,
      );

  PendingSyncEntry entry(
    String id, {
    String tripId = 'trip-1',
    int updatedAtMs = 100,
    int attemptCount = 0,
    String? lastError,
    PendingSyncState state = PendingSyncState.queued,
  }) =>
      PendingSyncEntry(
        operation: operation(id, tripId: tripId),
        state: state,
        attemptCount: attemptCount,
        lastError: lastError,
        updatedAtEpochMs: updatedAtMs,
      );

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    databasePath = p.join(await getDatabasesPath(), 'splitcrew-sync-queue.db');
  });

  setUp(() async {
    await deleteDatabase(databasePath);
  });

  tearDown(() async {
    await deleteDatabase(databasePath);
  });

  test('memory queue preserves submission order for same-millisecond operations', () async {
    final store = MemoryPendingSyncQueueStore();

    await store.upsert(entry('op-z', updatedAtMs: 100));
    await store.upsert(entry('op-a', updatedAtMs: 100));

    final entries = await store.loadAll();
    expect(entries.map((item) => item.operation.operationId), ['op-z', 'op-a']);
    expect(entries.map((item) => item.enqueueSequence), [1, 2]);
  });

  test('retry metadata update never moves an earlier operation behind later work', () async {
    final store = MemoryPendingSyncQueueStore();
    await store.upsert(entry('first', updatedAtMs: 100));
    await store.upsert(entry('second', updatedAtMs: 100));

    final originalFirst = (await store.loadAll()).first;
    await store.upsert(
      originalFirst.copyWith(
        attemptCount: 2,
        lastError: 'timeout',
        updatedAtEpochMs: 999,
      ),
    );

    final entries = await store.loadAll();
    expect(entries.map((item) => item.operation.operationId), ['first', 'second']);
    expect(entries.first.enqueueSequence, 1);
    expect(entries.first.attemptCount, 2);
    expect(entries.first.lastError, 'timeout');
  });

  test('clearForTrip leaves operations for other trips untouched', () async {
    final store = MemoryPendingSyncQueueStore();
    await store.upsert(entry('one', tripId: 'trip-a'));
    await store.upsert(
      entry(
        'two',
        tripId: 'trip-b',
        updatedAtMs: 200,
        state: PendingSyncState.blocked,
        attemptCount: 1,
        lastError: 'rejected',
      ),
    );

    await store.clearForTrip('trip-a');
    final entries = await store.loadAll();
    expect(entries, hasLength(1));
    expect(entries.single.operation.tripId, 'trip-b');
  });

  test('sqlite queue preserves sequence across retry and store restart', () async {
    final store = SqlitePendingSyncQueueStore();
    await store.upsert(entry('op-z', updatedAtMs: 100));
    await store.upsert(entry('op-a', updatedAtMs: 100));

    var entries = await store.loadAll();
    expect(entries.map((item) => item.operation.operationId), ['op-z', 'op-a']);
    expect(entries.map((item) => item.enqueueSequence), [1, 2]);

    await store.upsert(
      entries.first.copyWith(
        attemptCount: 3,
        lastError: 'socket timeout',
        updatedAtEpochMs: 1000,
      ),
    );
    await store.close();

    final restarted = SqlitePendingSyncQueueStore();
    entries = await restarted.loadAll();
    expect(entries.map((item) => item.operation.operationId), ['op-z', 'op-a']);
    expect(entries.map((item) => item.enqueueSequence), [1, 2]);
    expect(entries.first.attemptCount, 3);
    expect(entries.first.lastError, 'socket timeout');
    await restarted.clearForTrip('trip-1');
    await restarted.upsert(entry('after-clear', updatedAtMs: 5));
    entries = await restarted.loadAll();
    expect(entries.single.operation.operationId, 'after-clear');
    expect(entries.single.enqueueSequence, 3);
    await restarted.close();
  });

  test('schema v1 migrates pending operations deterministically without data loss', () async {
    final legacy = await openDatabase(
      databasePath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
CREATE TABLE pending_sync_operations (
  operation_id TEXT PRIMARY KEY,
  trip_id TEXT NOT NULL,
  actor_member_id TEXT NOT NULL,
  operation_json TEXT NOT NULL,
  state TEXT NOT NULL,
  attempt_count INTEGER NOT NULL,
  last_error TEXT,
  updated_at_ms INTEGER NOT NULL
)
''');
        await db.execute(
          'CREATE INDEX idx_pending_sync_trip '
          'ON pending_sync_operations(trip_id, updated_at_ms)',
        );
      },
    );

    Future<void> insertLegacy({
      required String operationId,
      required int updatedAtMs,
      required String state,
      required int attempts,
      String? error,
    }) async {
      final op = operation(operationId);
      await legacy.insert('pending_sync_operations', {
        'operation_id': op.operationId,
        'trip_id': op.tripId,
        'actor_member_id': op.actorMemberId,
        'operation_json': jsonEncode(op.toJson()),
        'state': state,
        'attempt_count': attempts,
        'last_error': error,
        'updated_at_ms': updatedAtMs,
      });
    }

    // Legacy order was updated_at_ms + operation_id. Migration uses that same
    // deterministic order because historical submission order was not stored.
    await insertLegacy(
      operationId: 'op-b',
      updatedAtMs: 200,
      state: 'blocked',
      attempts: 2,
      error: 'validation',
    );
    await insertLegacy(
      operationId: 'op-c',
      updatedAtMs: 100,
      state: 'queued',
      attempts: 1,
    );
    await insertLegacy(
      operationId: 'op-a',
      updatedAtMs: 100,
      state: 'queued',
      attempts: 0,
    );
    expect(await legacy.getVersion(), 1);
    await legacy.close();

    final migrated = SqlitePendingSyncQueueStore();
    final entries = await migrated.loadAll();

    expect(entries.map((item) => item.operation.operationId), ['op-a', 'op-c', 'op-b']);
    expect(entries.map((item) => item.enqueueSequence), [1, 2, 3]);
    expect(entries.last.state, PendingSyncState.blocked);
    expect(entries.last.attemptCount, 2);
    expect(entries.last.lastError, 'validation');

    await migrated.upsert(entry('op-new', updatedAtMs: 50));
    var afterNewInsert = await migrated.loadAll();
    expect(afterNewInsert.last.operation.operationId, 'op-new');
    expect(afterNewInsert.last.enqueueSequence, 4);

    await migrated.clearForTrip('trip-1');
    await migrated.upsert(entry('op-after-clear', updatedAtMs: 1));
    afterNewInsert = await migrated.loadAll();
    expect(afterNewInsert.single.operation.operationId, 'op-after-clear');
    expect(afterNewInsert.single.enqueueSequence, 5);
    await migrated.close();

    final upgraded = await openDatabase(databasePath);
    expect(await upgraded.getVersion(), 2);
    final columns = await upgraded.rawQuery('PRAGMA table_info(pending_sync_operations)');
    expect(columns.map((row) => row['name']), contains('enqueue_sequence'));
    await upgraded.close();
  });
}
