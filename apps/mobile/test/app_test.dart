import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:splitcrew_domain/splitcrew_domain.dart';
import 'package:splitcrew_mobile/src/app_state.dart';
import 'package:splitcrew_split_engine/splitcrew_split_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('creates and persists a local trip', () async {
    final controller = TripController();
    await controller.load();
    await controller.createTrip(name: 'Da Nang', ownerName: 'Lam');
    expect(controller.trip!.name, 'Da Nang');
    expect(controller.trip!.members.single.isOwner, isTrue);
  });

  test('adds expense and calculates settlement', () async {
    final controller = TripController();
    await controller.load();
    await controller.createTrip(name: 'Trip', ownerName: 'Lam');
    await controller.addMember('Hoang');
    final members = controller.trip!.members;
    final total = const Money(minorUnits: 100000, currencyCode: 'VND');
    final allocations = SplitEngine.equal(total: total, memberIds: members.map((m) => m.id));
    await controller.addExpense(
      title: 'Lunch',
      totalMinor: total.minorUnits,
      payers: [ExpensePayer(memberId: members.first.id, amount: total)],
      allocations: allocations,
    );
    expect(controller.trip!.expenses, hasLength(1));
    expect(controller.settlements, hasLength(1));
    expect(controller.settlements.single.amount.minorUnits, 50000);
  });
}
