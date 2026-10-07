import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:splitcrew_domain/splitcrew_domain.dart';
import 'package:splitcrew_mobile/src/app_state.dart';
import 'package:splitcrew_mobile/src/local_store.dart';
import 'package:splitcrew_mobile/src/receipt_store.dart';
import 'package:splitcrew_mobile/src/trip_summary.dart';
import 'package:splitcrew_split_engine/splitcrew_split_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('trip summary renders canonical totals, balances and settlement', (tester) async {
    final controller = TripController(
      repository: MemoryTripRepository(),
      receiptFileStore: MemoryReceiptFileStore(),
    );
    await controller.load();
    await controller.createTrip(name: 'Da Nang Crew', ownerName: 'Lam');
    await controller.addMember('An');

    final members = controller.trip!.members;
    const total = Money(minorUnits: 120000, currencyCode: 'VND');
    await controller.addExpense(
      title: 'Dinner',
      totalMinor: total.minorUnits,
      payers: [
        ExpensePayer(memberId: members.first.id, amount: total),
      ],
      allocations: SplitEngine.equal(
        total: total,
        memberIds: members.map((member) => member.id),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TripSummaryPage(
          controller: controller,
          isCanonicalReplica: true,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Da Nang Crew'), findsOneWidget);
    expect(find.text('Owner-committed canonical snapshot'), findsOneWidget);
    expect(find.text('120.000 VND'), findsWidgets);
    expect(find.text('Balances'), findsOneWidget);
    expect(find.text('Suggested settlement'), findsOneWidget);
    expect(find.textContaining('An → Lam'), findsOneWidget);
    expect(find.textContaining('revision'), findsOneWidget);
    expect(find.widgetWithText(FloatingActionButton, 'Save PNG'), findsOneWidget);
  });
}
