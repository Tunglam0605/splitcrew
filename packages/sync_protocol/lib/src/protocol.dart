enum SyncRole { owner, admin, member }

enum SyncOperationType {
  createExpense,
  updateExpense,
  deleteExpense,
  addMember,
  renameMember,
  updatePaymentAccount,
  markSettlement,
}

enum SyncResultStatus { accepted, duplicate, conflict, rejected }

final class SyncOperation {
  SyncOperation({
    required this.operationId,
    required this.tripId,
    required this.actorMemberId,
    required this.expectedTripRevision,
    required this.type,
    required Map<String, Object?> payload,
    required this.createdAtEpochMs,
    this.protocolVersion = 1,
  }) : payload = Map.unmodifiable(payload) {
    if (protocolVersion != 1) throw ArgumentError('Unsupported protocol version.');
    if (operationId.trim().isEmpty || tripId.trim().isEmpty || actorMemberId.trim().isEmpty) {
      throw ArgumentError('Operation, trip and actor identifiers are required.');
    }
    if (expectedTripRevision < 0) throw ArgumentError('Expected revision must be >= 0.');
  }

  final int protocolVersion;
  final String operationId;
  final String tripId;
  final String actorMemberId;
  final int expectedTripRevision;
  final SyncOperationType type;
  final Map<String, Object?> payload;
  final int createdAtEpochMs;

  Map<String, Object?> toJson() => {
        'protocolVersion': protocolVersion,
        'operationId': operationId,
        'tripId': tripId,
        'actorMemberId': actorMemberId,
        'expectedTripRevision': expectedTripRevision,
        'type': type.name,
        'payload': payload,
        'createdAtEpochMs': createdAtEpochMs,
      };

  factory SyncOperation.fromJson(Map<String, dynamic> json) => SyncOperation(
        protocolVersion: json['protocolVersion'] as int? ?? 1,
        operationId: json['operationId'] as String,
        tripId: json['tripId'] as String,
        actorMemberId: json['actorMemberId'] as String,
        expectedTripRevision: json['expectedTripRevision'] as int,
        type: SyncOperationType.values.byName(json['type'] as String),
        payload: Map<String, Object?>.from(json['payload'] as Map? ?? const {}),
        createdAtEpochMs: json['createdAtEpochMs'] as int,
      );
}

final class CommittedSyncEvent {
  CommittedSyncEvent({
    required this.eventId,
    required this.tripId,
    required this.revision,
    required this.operationId,
    required this.type,
    required Map<String, Object?> payload,
    required this.committedAtEpochMs,
  }) : payload = Map.unmodifiable(payload) {
    if (revision <= 0) throw ArgumentError('Committed revision must be > 0.');
  }

  final String eventId;
  final String tripId;
  final int revision;
  final String operationId;
  final SyncOperationType type;
  final Map<String, Object?> payload;
  final int committedAtEpochMs;

  Map<String, Object?> toJson() => {
        'eventId': eventId,
        'tripId': tripId,
        'revision': revision,
        'operationId': operationId,
        'type': type.name,
        'payload': payload,
        'committedAtEpochMs': committedAtEpochMs,
      };

  factory CommittedSyncEvent.fromJson(Map<String, dynamic> json) => CommittedSyncEvent(
        eventId: json['eventId'] as String,
        tripId: json['tripId'] as String,
        revision: json['revision'] as int,
        operationId: json['operationId'] as String,
        type: SyncOperationType.values.byName(json['type'] as String),
        payload: Map<String, Object?>.from(json['payload'] as Map? ?? const {}),
        committedAtEpochMs: json['committedAtEpochMs'] as int,
      );
}

final class SyncOperationResult {
  const SyncOperationResult({
    required this.operationId,
    required this.status,
    required this.canonicalTripRevision,
    this.event,
    this.errorCode,
    this.message,
  });

  final String operationId;
  final SyncResultStatus status;
  final int canonicalTripRevision;
  final CommittedSyncEvent? event;
  final String? errorCode;
  final String? message;

  Map<String, Object?> toJson() => {
        'operationId': operationId,
        'status': status.name,
        'canonicalTripRevision': canonicalTripRevision,
        if (event != null) 'event': event!.toJson(),
        if (errorCode != null) 'errorCode': errorCode,
        if (message != null) 'message': message,
      };

  factory SyncOperationResult.fromJson(Map<String, dynamic> json) => SyncOperationResult(
        operationId: json['operationId'] as String,
        status: SyncResultStatus.values.byName(json['status'] as String),
        canonicalTripRevision: json['canonicalTripRevision'] as int,
        event: json['event'] == null
            ? null
            : CommittedSyncEvent.fromJson(Map<String, dynamic>.from(json['event'] as Map)),
        errorCode: json['errorCode'] as String?,
        message: json['message'] as String?,
      );
}

final class TripSnapshotEnvelope {
  TripSnapshotEnvelope({
    required this.tripId,
    required this.revision,
    required Map<String, Object?> snapshot,
  }) : snapshot = Map.unmodifiable(snapshot);

  final String tripId;
  final int revision;
  final Map<String, Object?> snapshot;

  Map<String, Object?> toJson() => {
        'tripId': tripId,
        'revision': revision,
        'snapshot': snapshot,
      };

  factory TripSnapshotEnvelope.fromJson(Map<String, dynamic> json) => TripSnapshotEnvelope(
        tripId: json['tripId'] as String,
        revision: json['revision'] as int,
        snapshot: Map<String, Object?>.from(json['snapshot'] as Map),
      );
}
