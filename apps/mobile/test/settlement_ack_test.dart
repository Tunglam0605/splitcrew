import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:splitcrew_domain/splitcrew_domain.dart';
import 'package:splitcrew_mobile/src/app_state.dart';
import 'package:splitcrew_mobile/src/local_store.dart';
import 'package:splitcrew_mobile/src/sync_queue_store.dart';
import 'package:splitcrew_mobile/src/sync_service.dart';
import 'package:splitcrew_split_engine/splitcrew_split_engine.dart';
import 'package:splitcrew_sync_protocol/splitcrew_sync_protocol.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<(TripController, MemoryTripRepository)> fixture() async {
    final repository = MemoryTripRepository();
    final controller = TripController(repository: repository);
    await controller.load();
    await controller.createTrip(name: 'Crew', ownerName: 'Owner');
    await controller.addMember('An');
    final members = controller.trip!.members;
    const total = Money(minorUnits: 120000, currencyCode: 'VND');
    await controller.addExpense(
      title: 'Dinner',
      totalMinor: total.minorUnits,
      payers: [ExpensePayer(memberId: members.first.id, amount: total)],
      allocations: SplitEngine.equal(
        total: total,
        memberIds: members.map((member) => member.id),
      ),
    );
    return (controller, repository);
  }

  test('acknowledgement clears the suggested debt and survives reload', () async {
    final (controller, repository) = await fixture();
    final transfer = controller.settlements.single;
    final debtor = transfer.fromMemberId;

    await controller.acknowledgeSettlement(
      fromMemberId: transfer.fromMemberId,
      toMemberId: transfer.toMemberId,
      amountMinor: transfer.amount.minorUnits,
      confirmedByMemberId: debtor,
    );

    expect(controller.trip!.settlementAcknowledgements, hasLength(1));
    expect(controller.settlements, isEmpty);
    expect(
      controller.balances.map((balance) => balance.balance.minorUnits),
      everyElement(0),
    );

    final reloaded = TripController(repository: repository);
    await reloaded.load();
    expect(reloaded.trip!.settlementAcknowledgements, hasLength(1));
    expect(reloaded.settlements, isEmpty);

    await expectLater(
      reloaded.acknowledgeSettlement(
        fromMemberId: transfer.fromMemberId,
        toMemberId: transfer.toMemberId,
        amountMinor: transfer.amount.minorUnits,
        confirmedByMemberId: debtor,
      ),
      throwsStateError,
    );
  });

  test('historical acknowledgement remains valid after later expenses change current debt', () async {
    final (controller, repository) = await fixture();
    final firstTransfer = controller.settlements.single;
    await controller.acknowledgeSettlement(
      fromMemberId: firstTransfer.fromMemberId,
      toMemberId: firstTransfer.toMemberId,
      amountMinor: firstTransfer.amount.minorUnits,
      confirmedByMemberId: firstTransfer.fromMemberId,
    );

    final members = controller.trip!.members;
    const laterTotal = Money(minorUnits: 40000, currencyCode: 'VND');
    await controller.addExpense(
      title: 'Taxi after payment',
      totalMinor: laterTotal.minorUnits,
      payers: [ExpensePayer(memberId: members.last.id, amount: laterTotal)],
      allocations: SplitEngine.equal(
        total: laterTotal,
        memberIds: members.map((member) => member.id),
      ),
    );

    expect(controller.trip!.settlementAcknowledgements, hasLength(1));
    expect(controller.settlements, hasLength(1));
    expect(controller.settlements.single.fromMemberId, members.first.id);
    expect(controller.settlements.single.toMemberId, members.last.id);
    expect(controller.settlements.single.amount.minorUnits, 20000);

    final reloaded = TripController(repository: repository);
    await reloaded.load();
    expect(reloaded.loadError, isNull);
    expect(reloaded.trip!.settlementAcknowledgements, hasLength(1));
    expect(reloaded.settlements.single.amount.minorUnits, 20000);
  });

  test('offline member acknowledgement queues without mutating canonical replica', () async {
    final (source, _) = await fixture();
    final transfer = source.settlements.single;
    final repository = MemoryTripRepository();
    await repository.save(
      StoredTrip.fromJson(Map<String, dynamic>.from(source.trip!.toJson())),
    );
    final replica = TripController(repository: repository);
    await replica.load();
    final queue = MemoryPendingSyncQueueStore();
    final sync = await MobileSyncController.memberSessionForTesting(
      tripController: replica,
      memberId: transfer.fromMemberId,
      canonicalRevision: replica.trip!.version,
      queueStore: queue,
      online: false,
    );

    final disposition = await sync.markSettlement(
      fromMemberId: transfer.fromMemberId,
      toMemberId: transfer.toMemberId,
      amountMinor: transfer.amount.minorUnits,
    );

    expect(disposition, SyncWriteDisposition.queued);
    expect(replica.trip!.settlementAcknowledgements, isEmpty);
    expect(replica.settlements, hasLength(1));
    final entries = await queue.loadAll();
    expect(entries, hasLength(1));
    expect(entries.single.operation.type, SyncOperationType.markSettlement);
    expect(entries.single.operation.payload['fromMemberId'], transfer.fromMemberId);
    expect(entries.single.operation.payload['toMemberId'], transfer.toMemberId);
    expect(entries.single.operation.payload['amountMinor'], transfer.amount.minorUnits);
  });

  test('host settlement acknowledgement is idempotent and cannot double-clear debt', () async {
    final (controller, _) = await fixture();
    final transfer = controller.settlements.single;
    final backend = MobileSyncController.hostBackendForTesting(controller);
    final operation = SyncOperation(
      operationId: 'settlement-1',
      tripId: controller.trip!.id,
      actorMemberId: transfer.fromMemberId,
      expectedTripRevision: controller.trip!.version,
      type: SyncOperationType.markSettlement,
      payload: {
        'fromMemberId': transfer.fromMemberId,
        'toMemberId': transfer.toMemberId,
        'amountMinor': transfer.amount.minorUnits,
      },
      createdAtEpochMs: 1,
    );

    final accepted = await backend.apply(operation);
    expect(accepted.status, SyncResultStatus.accepted);
    expect(controller.trip!.settlementAcknowledgements, hasLength(1));
    expect(controller.settlements, isEmpty);

    final duplicate = await backend.apply(operation);
    expect(duplicate.status, SyncResultStatus.duplicate);
    expect(controller.trip!.settlementAcknowledgements, hasLength(1));

    final staleMeaning = await backend.apply(
      SyncOperation(
        operationId: 'settlement-2',
        tripId: controller.trip!.id,
        actorMemberId: transfer.fromMemberId,
        expectedTripRevision: controller.trip!.version,
        type: SyncOperationType.markSettlement,
        payload: {
          'fromMemberId': transfer.fromMemberId,
          'toMemberId': transfer.toMemberId,
          'amountMinor': transfer.amount.minorUnits,
        },
        createdAtEpochMs: 2,
      ),
    );
    expect(staleMeaning.status, SyncResultStatus.conflict);
    expect(staleMeaning.errorCode, 'ENTITY_VERSION_CONFLICT');
    expect(controller.trip!.settlementAcknowledgements, hasLength(1));
  });

  test('member cannot acknowledge another member outgoing transfer', () async {
    final (controller, _) = await fixture();
    final transfer = controller.settlements.single;
    await controller.addMember('Binh');
    final otherMember = controller.trip!.members.firstWhere(
      (member) => !member.isOwner && member.id != transfer.fromMemberId,
    );
    final backend = MobileSyncController.hostBackendForTesting(controller);

    final result = await backend.apply(
      SyncOperation(
        operationId: 'settlement-forbidden',
        tripId: controller.trip!.id,
        actorMemberId: otherMember.id,
        expectedTripRevision: controller.trip!.version,
        type: SyncOperationType.markSettlement,
        payload: {
          'fromMemberId': transfer.fromMemberId,
          'toMemberId': transfer.toMemberId,
          'amountMinor': transfer.amount.minorUnits,
        },
        createdAtEpochMs: 3,
      ),
    );

    expect(result.status, SyncResultStatus.rejected);
    expect(result.errorCode, 'OPERATION_FORBIDDEN');
    expect(controller.trip!.settlementAcknowledgements, isEmpty);
  });

  test('owner may acknowledge a current suggested transfer', () async {
    final (controller, _) = await fixture();
    final transfer = controller.settlements.single;
    final owner = controller.trip!.members.firstWhere((member) => member.isOwner);
    final backend = MobileSyncController.hostBackendForTesting(controller);

    final result = await backend.apply(
      SyncOperation(
        operationId: 'settlement-owner',
        tripId: controller.trip!.id,
        actorMemberId: owner.id,
        expectedTripRevision: controller.trip!.version,
        type: SyncOperationType.markSettlement,
        payload: {
          'fromMemberId': transfer.fromMemberId,
          'toMemberId': transfer.toMemberId,
          'amountMinor': transfer.amount.minorUnits,
        },
        createdAtEpochMs: 4,
      ),
    );

    expect(result.status, SyncResultStatus.accepted);
    expect(controller.trip!.settlementAcknowledgements.single.confirmedByMemberId, owner.id);
    expect(controller.settlements, isEmpty);
  });
}
