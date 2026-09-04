import 'package:splitcrew_sync_protocol/splitcrew_sync_protocol.dart';

abstract interface class HostTripBackend {
  String get tripId;
  int get revision;

  bool canSubmit({required String memberId, required SyncOperationType type});

  Future<TripSnapshotEnvelope> snapshot();

  Future<SyncOperationResult> apply(SyncOperation operation);
}
