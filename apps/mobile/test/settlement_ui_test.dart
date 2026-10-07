import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:splitcrew_domain/splitcrew_domain.dart';
import 'package:splitcrew_mobile/src/app_state.dart';
import 'package:splitcrew_mobile/src/local_store.dart';
import 'package:splitcrew_mobile/src/settlement_ui.dart';
import 'package:splitcrew_mobile/src/sync_queue_store.dart';
import 'package:splitcrew_mobile/src/sync_service.dart';
import 'package:splitcrew_split_engine/splitcrew_split_engine.dart';
import 'package:splitcrew_sync_protocol/splitcrew_sync_protocol.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('member confirms outgoing settlement and queues acknowledgement offline', (tester) async {
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

    final transfer = controller.settlements.single;
    final queue = MemoryPendingSyncQueueStore();
    final sync = await MobileSyncController.memberSessionForTesting(
      tripController: controller,
      memberId: transfer.fromMemberId,
      canonicalRevision: controller.trip!.version,
      queueStore: queue,
      online: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => confirmAndRecordSettlement(
                context,
                controller: controller,
                sync: sync,
                transfer: transfer,
              ),
              child: const Text('Open settlement'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open settlement'));
    await tester.pump();
    expect(find.text('Record payment?'), findsOneWidget);
    expect(find.textContaining('changes the canonical settlement ledger'), findsOneWidget);

    await tester.tap(find.text('Record paid'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final entries = await queue.loadAll();
    expect(entries, hasLength(1));
    expect(entries.single.operation.type, SyncOperationType.markSettlement);
    expect(controller.trip!.settlementAcknowledgements, isEmpty);
    expect(find.textContaining('queued for owner validation'), findsOneWidget);
  });
}
