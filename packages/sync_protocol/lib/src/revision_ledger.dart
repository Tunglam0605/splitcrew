import 'protocol.dart';

final class SyncRevisionLedger {
  SyncRevisionLedger({required this.tripId, int initialRevision = 0}) : _revision = initialRevision {
    if (initialRevision < 0) throw ArgumentError('Initial revision must be >= 0.');
  }

  final String tripId;
  int _revision;
  final Map<String, SyncOperationResult> _resultsByOperationId = {};

  int get revision => _revision;

  SyncOperationResult? priorResult(String operationId) => _resultsByOperationId[operationId];

  SyncOperationResult evaluate(SyncOperation operation) {
    final prior = _resultsByOperationId[operation.operationId];
    if (prior != null) {
      return SyncOperationResult(
        operationId: prior.operationId,
        status: SyncResultStatus.duplicate,
        canonicalTripRevision: prior.canonicalTripRevision,
        event: prior.event,
        errorCode: prior.errorCode,
        message: 'Operation already processed.',
      );
    }
    if (operation.tripId != tripId) {
      final rejected = SyncOperationResult(
        operationId: operation.operationId,
        status: SyncResultStatus.rejected,
        canonicalTripRevision: _revision,
        errorCode: 'TRIP_MISMATCH',
        message: 'Operation belongs to a different trip.',
      );
      _resultsByOperationId[operation.operationId] = rejected;
      return rejected;
    }
    if (operation.expectedTripRevision != _revision) {
      final conflict = SyncOperationResult(
        operationId: operation.operationId,
        status: SyncResultStatus.conflict,
        canonicalTripRevision: _revision,
        errorCode: 'STALE_REVISION',
        message: 'Refresh the canonical snapshot before retrying.',
      );
      _resultsByOperationId[operation.operationId] = conflict;
      return conflict;
    }
    return SyncOperationResult(
      operationId: operation.operationId,
      status: SyncResultStatus.accepted,
      canonicalTripRevision: _revision + 1,
    );
  }

  SyncOperationResult commit({
    required SyncOperation operation,
    required String eventId,
    required Map<String, Object?> canonicalPayload,
    required int committedAtEpochMs,
  }) {
    final existing = _resultsByOperationId[operation.operationId];
    if (existing != null) return existing;
    if (operation.tripId != tripId || operation.expectedTripRevision != _revision) {
      return evaluate(operation);
    }
    _revision += 1;
    final event = CommittedSyncEvent(
      eventId: eventId,
      tripId: tripId,
      revision: _revision,
      operationId: operation.operationId,
      type: operation.type,
      payload: canonicalPayload,
      committedAtEpochMs: committedAtEpochMs,
    );
    final accepted = SyncOperationResult(
      operationId: operation.operationId,
      status: SyncResultStatus.accepted,
      canonicalTripRevision: _revision,
      event: event,
    );
    _resultsByOperationId[operation.operationId] = accepted;
    return accepted;
  }
}
