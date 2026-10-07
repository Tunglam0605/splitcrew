import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:splitcrew_mobile/src/app_state.dart';
import 'package:splitcrew_mobile/src/local_store.dart';
import 'package:splitcrew_mobile/src/member_profile_page.dart';
import 'package:splitcrew_mobile/src/sync_queue_store.dart';
import 'package:splitcrew_mobile/src/sync_service.dart';
import 'package:splitcrew_sync_protocol/splitcrew_sync_protocol.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('offline member profile save queues rename without mutating cached replica', (tester) async {
    final repository = MemoryTripRepository();
    final controller = TripController(repository: repository);
    await controller.load();
    await controller.createTrip(name: 'Crew', ownerName: 'Owner');
    await controller.addMember('An');
    final member = controller.trip!.members.last;
    final queue = MemoryPendingSyncQueueStore();
    final sync = await MobileSyncController.memberSessionForTesting(
      tripController: controller,
      memberId: member.id,
      canonicalRevision: controller.trip!.version,
      queueStore: queue,
      online: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MemberProfilePage(
          controller: controller,
          sync: sync,
          memberId: member.id,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('My crew profile'), findsOneWidget);
    expect(find.textContaining('Never enter a banking password'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'An Nguyen');
    await tester.tap(find.text('Save profile'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final entries = await queue.loadAll();
    expect(entries, hasLength(1));
    expect(entries.single.operation.type, SyncOperationType.renameMember);
    expect(entries.single.operation.payload['name'], 'An Nguyen');
    expect(controller.memberName(member.id), 'An');
  });
}
