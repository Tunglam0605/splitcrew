import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:splitcrew_mobile/src/app_state.dart';
import 'package:splitcrew_mobile/src/local_store.dart';
import 'package:splitcrew_mobile/src/sync_queue_store.dart';
import 'package:splitcrew_mobile/src/sync_service.dart';
import 'package:splitcrew_sync_protocol/splitcrew_sync_protocol.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<TripController> crewController() async {
    final controller = TripController(repository: MemoryTripRepository());
    await controller.load();
    await controller.createTrip(name: 'Crew', ownerName: 'Owner');
    await controller.addMember('An');
    await controller.addMember('Binh');
    return controller;
  }

  test('offline member profile mutations are queued without mutating canonical cache', () async {
    final source = await crewController();
    final member = source.trip!.members[1];
    final repository = MemoryTripRepository();
    await repository.save(StoredTrip.fromJson(Map<String, dynamic>.from(source.trip!.toJson())));
    final replica = TripController(repository: repository);
    await replica.load();
    final queue = MemoryPendingSyncQueueStore();
    final sync = await MobileSyncController.memberSessionForTesting(
      tripController: replica,
      memberId: member.id,
      canonicalRevision: replica.trip!.version,
      queueStore: queue,
      online: false,
    );

    final renameDisposition = await sync.renameMember(
      memberId: member.id,
      name: 'An Nguyen',
    );
    final paymentDisposition = await sync.updatePaymentAccount(
      memberId: member.id,
      holderName: 'NGUYEN VAN AN',
      bankBin: '970422',
      accountIdentifier: '5566778899',
    );

    expect(renameDisposition, SyncWriteDisposition.queued);
    expect(paymentDisposition, SyncWriteDisposition.queued);
    expect(replica.memberName(member.id), 'An');
    expect(replica.paymentAccountForMember(member.id), isNull);

    final entries = await queue.loadAll();
    expect(entries, hasLength(2));
    expect(entries[0].operation.type, SyncOperationType.renameMember);
    expect(entries[0].operation.payload['memberId'], member.id);
    expect(entries[0].operation.payload['expectedMemberVersion'], member.version);
    expect(entries[1].operation.type, SyncOperationType.updatePaymentAccount);
    expect(entries[1].operation.payload.containsKey('expectedPaymentAccountVersion'), isTrue);
    expect(entries[1].operation.payload['expectedPaymentAccountVersion'], isNull);
  });


  test('host rename is idempotent and rejects stale member entity versions', () async {
    final controller = await crewController();
    final member = controller.trip!.members[1];
    final backend = MobileSyncController.hostBackendForTesting(controller);

    final acceptedOperation = SyncOperation(
      operationId: 'rename-1',
      tripId: controller.trip!.id,
      actorMemberId: member.id,
      expectedTripRevision: controller.trip!.version,
      type: SyncOperationType.renameMember,
      payload: {
        'memberId': member.id,
        'expectedMemberVersion': member.version,
        'name': 'An Nguyen',
      },
      createdAtEpochMs: 1,
    );
    final accepted = await backend.apply(acceptedOperation);
    expect(accepted.status, SyncResultStatus.accepted);
    expect(controller.memberName(member.id), 'An Nguyen');

    final duplicate = await backend.apply(acceptedOperation);
    expect(duplicate.status, SyncResultStatus.duplicate);

    final stale = await backend.apply(
      SyncOperation(
        operationId: 'rename-stale',
        tripId: controller.trip!.id,
        actorMemberId: member.id,
        expectedTripRevision: controller.trip!.version,
        type: SyncOperationType.renameMember,
        payload: {
          'memberId': member.id,
          'expectedMemberVersion': member.version,
          'name': 'Stale Rename',
        },
        createdAtEpochMs: 2,
      ),
    );
    expect(stale.status, SyncResultStatus.conflict);
    expect(stale.errorCode, 'ENTITY_VERSION_CONFLICT');
    expect(controller.memberName(member.id), 'An Nguyen');
  });

  test('non-owner cannot rename another member profile', () async {
    final controller = await crewController();
    final target = controller.trip!.members[1];
    final actor = controller.trip!.members[2];
    final backend = MobileSyncController.hostBackendForTesting(controller);

    final result = await backend.apply(
      SyncOperation(
        operationId: 'rename-other',
        tripId: controller.trip!.id,
        actorMemberId: actor.id,
        expectedTripRevision: controller.trip!.version,
        type: SyncOperationType.renameMember,
        payload: {
          'memberId': target.id,
          'expectedMemberVersion': target.version,
          'name': 'Not Allowed',
        },
        createdAtEpochMs: 3,
      ),
    );

    expect(result.status, SyncResultStatus.rejected);
    expect(result.errorCode, 'OPERATION_FORBIDDEN');
    expect(controller.memberName(target.id), 'An');

    final paymentResult = await backend.apply(
      SyncOperation(
        operationId: 'payment-other',
        tripId: controller.trip!.id,
        actorMemberId: actor.id,
        expectedTripRevision: controller.trip!.version,
        type: SyncOperationType.updatePaymentAccount,
        payload: {
          'memberId': target.id,
          'expectedPaymentAccountVersion': null,
          'holderName': 'NOT ALLOWED',
          'bankBin': '970422',
          'accountIdentifier': '1234567890',
        },
        createdAtEpochMs: 4,
      ),
    );
    expect(paymentResult.status, SyncResultStatus.rejected);
    expect(paymentResult.errorCode, 'OPERATION_FORBIDDEN');
    expect(controller.paymentAccountForMember(target.id), isNull);
  });

  test('payment profile create and update use nullable entity-version semantics', () async {
    final controller = await crewController();
    final member = controller.trip!.members[1];
    final backend = MobileSyncController.hostBackendForTesting(controller);

    final createResult = await backend.apply(
      SyncOperation(
        operationId: 'payment-create',
        tripId: controller.trip!.id,
        actorMemberId: member.id,
        expectedTripRevision: controller.trip!.version,
        type: SyncOperationType.updatePaymentAccount,
        payload: {
          'memberId': member.id,
          'expectedPaymentAccountVersion': null,
          'holderName': 'NGUYEN VAN AN',
          'bankBin': '970422',
          'accountIdentifier': '5566778899',
        },
        createdAtEpochMs: 4,
      ),
    );
    expect(createResult.status, SyncResultStatus.accepted);
    final created = controller.trip!.paymentAccounts.singleWhere((account) => account.memberId == member.id);
    expect(created.version, 0);

    final staleCreate = await backend.apply(
      SyncOperation(
        operationId: 'payment-stale',
        tripId: controller.trip!.id,
        actorMemberId: member.id,
        expectedTripRevision: controller.trip!.version,
        type: SyncOperationType.updatePaymentAccount,
        payload: {
          'memberId': member.id,
          'expectedPaymentAccountVersion': null,
          'holderName': 'NGUYEN VAN AN',
          'bankBin': '970422',
          'accountIdentifier': '0000000000',
        },
        createdAtEpochMs: 5,
      ),
    );
    expect(staleCreate.status, SyncResultStatus.conflict);
    expect(staleCreate.errorCode, 'ENTITY_VERSION_CONFLICT');

    final updateResult = await backend.apply(
      SyncOperation(
        operationId: 'payment-update',
        tripId: controller.trip!.id,
        actorMemberId: member.id,
        expectedTripRevision: controller.trip!.version,
        type: SyncOperationType.updatePaymentAccount,
        payload: {
          'memberId': member.id,
          'expectedPaymentAccountVersion': created.version,
          'holderName': 'NGUYEN VAN AN',
          'bankBin': '970422',
          'accountIdentifier': '9988776655',
        },
        createdAtEpochMs: 6,
      ),
    );
    expect(updateResult.status, SyncResultStatus.accepted);
    final updated = controller.trip!.paymentAccounts.singleWhere((account) => account.memberId == member.id);
    expect(updated.version, 1);
    expect(updated.accountIdentifier, '9988776655');
  });
}
