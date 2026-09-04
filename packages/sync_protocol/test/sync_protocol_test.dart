import 'package:splitcrew_sync_protocol/splitcrew_sync_protocol.dart';
import 'package:test/test.dart';

SyncOperation op({String id = 'op-1', int revision = 0, String trip = 'trip-1'}) => SyncOperation(
      operationId: id,
      tripId: trip,
      actorMemberId: 'member-1',
      expectedTripRevision: revision,
      type: SyncOperationType.createExpense,
      payload: const {'title': 'Dinner'},
      createdAtEpochMs: 1000,
    );

void main() {
  test('invite round-trips and exposes endpoint', () {
    const invite = LocalHostInvite(
      tripId: 'trip-1',
      memberId: 'member-1',
      hostId: 'host-device-1',
      host: '192.168.4.1',
      port: 45821,
      token: '0123456789abcdef0123456789abcdef',
      expiresAtEpochMs: 2000,
    );
    final decoded = LocalHostInvite.decode(invite.encode());
    expect(decoded.tripId, invite.tripId);
    expect(decoded.memberId, invite.memberId);
    expect(decoded.hostId, invite.hostId);
    expect(decoded.baseUri.toString(), 'http://192.168.4.1:45821');
    expect(decoded.isExpiredAt(1999), isFalse);
    expect(decoded.isExpiredAt(2000), isTrue);
  });

  test('stale expected revision returns conflict without advancing revision', () {
    final ledger = SyncRevisionLedger(tripId: 'trip-1', initialRevision: 4);
    final result = ledger.evaluate(op(revision: 3));
    expect(result.status, SyncResultStatus.conflict);
    expect(result.canonicalTripRevision, 4);
    expect(ledger.revision, 4);
  });

  test('commit advances canonical revision exactly once', () {
    final ledger = SyncRevisionLedger(tripId: 'trip-1');
    final operation = op();
    final result = ledger.commit(
      operation: operation,
      eventId: 'event-1',
      canonicalPayload: const {'expenseId': 'expense-1'},
      committedAtEpochMs: 1200,
    );
    expect(result.status, SyncResultStatus.accepted);
    expect(result.canonicalTripRevision, 1);
    expect(result.event?.revision, 1);
    expect(ledger.revision, 1);

    final duplicate = ledger.evaluate(operation);
    expect(duplicate.status, SyncResultStatus.duplicate);
    expect(duplicate.canonicalTripRevision, 1);
    expect(ledger.revision, 1);
  });

  test('operation JSON round-trips', () {
    final original = op();
    final decoded = SyncOperation.fromJson(Map<String, dynamic>.from(original.toJson()));
    expect(decoded.operationId, original.operationId);
    expect(decoded.type, original.type);
    expect(decoded.payload['title'], 'Dinner');
  });
}
