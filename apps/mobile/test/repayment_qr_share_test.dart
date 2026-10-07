import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:splitcrew_domain/splitcrew_domain.dart';
import 'package:splitcrew_mobile/src/app_state.dart';
import 'package:splitcrew_mobile/src/local_store.dart';
import 'package:splitcrew_mobile/src/payment_ui.dart';
import 'package:splitcrew_mobile/src/receipt_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('repayment QR exposes save and share actions', (tester) async {
    final controller = TripController(
      repository: MemoryTripRepository(),
      receiptFileStore: MemoryReceiptFileStore(),
    );
    await controller.load();
    await controller.createTrip(name: 'Trip', ownerName: 'Lam');
    await controller.addMember('An');

    final owner = controller.trip!.members.first;
    final recipient = controller.trip!.members.last;
    await controller.upsertPaymentAccount(
      memberId: recipient.id,
      holderName: 'NGUYEN VAN AN',
      bankBin: '970422',
      accountIdentifier: '5566778899',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: RepaymentQrPage(
          controller: controller,
          fromMemberId: owner.id,
          toMemberId: recipient.id,
          amount: const Money(minorUnits: 527000, currencyCode: 'VND'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('Share QR'), findsOneWidget);
    expect(find.byIcon(Icons.share_rounded), findsOneWidget);
    expect(find.text('Save QR'), findsOneWidget);
    expect(find.textContaining('527.000'), findsWidgets);
    expect(find.textContaining('NGUYEN VAN AN'), findsWidgets);
  });
}
