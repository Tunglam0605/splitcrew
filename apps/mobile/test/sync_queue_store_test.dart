import 'package:flutter_test/flutter_test.dart';
import 'package:splitcrew_mobile/src/sync_queue_store.dart';
import 'package:splitcrew_sync_protocol/splitcrew_sync_protocol.dart';

void main() {
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

  test('memory queue preserves operation identity and order', () async {
    final store = MemoryPendingSyncQueueStore();
    await store.upsert(
      PendingSyncEntry(
        operation: operation('op-b'),
        state: PendingSyncState.queued,
        attemptCount: 0,
        updatedAtEpochMs: 200,
      ),
    );
    await store.upsert(
      PendingSyncEntry(
        operation: operation('op-a'),
        state: PendingSyncState.queued,
        attemptCount: 0,
        updatedAtEpochMs: 100,
      ),
    );

    final entries = await store.loadAll();
    expect(entries.map((entry) => entry.operation.operationId), ['op-a', 'op-b']);
    expect(entries.first.operation.expectedTripRevision, 4);
  });

  test('upsert updates retry metadata without duplicating operation', () async {
    final store = MemoryPendingSyncQueueStore();
    final original = PendingSyncEntry(
      operation: operation('op-1'),
      state: PendingSyncState.queued,
      attemptCount: 0,
      updatedAtEpochMs: 100,
    );
    await store.upsert(original);
    await store.upsert(
      original.copyWith(
        attemptCount: 2,
        lastError: 'timeout',
        updatedAtEpochMs: 300,
      ),
    );

    final entries = await store.loadAll();
    expect(entries, hasLength(1));
    expect(entries.single.attemptCount, 2);
    expect(entries.single.lastError, 'timeout');
  });

  test('clearForTrip leaves operations for other trips untouched', () async {
    final store = MemoryPendingSyncQueueStore();
    await store.upsert(
      PendingSyncEntry(
        operation: operation('one', tripId: 'trip-a'),
        state: PendingSyncState.queued,
        attemptCount: 0,
        updatedAtEpochMs: 100,
      ),
    );
    await store.upsert(
      PendingSyncEntry(
        operation: operation('two', tripId: 'trip-b'),
        state: PendingSyncState.blocked,
        attemptCount: 1,
        lastError: 'rejected',
        updatedAtEpochMs: 200,
      ),
    );

    await store.clearForTrip('trip-a');
    final entries = await store.loadAll();
    expect(entries, hasLength(1));
    expect(entries.single.operation.tripId, 'trip-b');
  });
}
