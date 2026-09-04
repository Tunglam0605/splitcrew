import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:splitcrew_domain/splitcrew_domain.dart';
import 'package:splitcrew_mobile/src/app_state.dart';
import 'package:splitcrew_mobile/src/local_store.dart';
import 'package:splitcrew_split_engine/splitcrew_split_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  TripController controller() => TripController(repository: MemoryTripRepository());

  test('creates and reloads a local trip through repository', () async {
    final repository = MemoryTripRepository();
    final first = TripController(repository: repository);
    await first.load();
    await first.createTrip(name: 'Da Nang', ownerName: 'Lam');
    final second = TripController(repository: repository);
    await second.load();
    expect(second.trip!.name, 'Da Nang');
    expect(second.trip!.members.single.isOwner, isTrue);
    expect(second.trip!.id, isNotEmpty);
  });

  test('imports a valid v0.1 SharedPreferences trip once', () async {
    SharedPreferences.setMockInitialValues({
      'splitcrew.trip.v1': jsonEncode({
        'id': 'legacy-trip',
        'name': 'Legacy trip',
        'currencyCode': 'VND',
        'members': [
          {'id': 'legacy-owner', 'name': 'Lam', 'isOwner': true},
        ],
        'expenses': <Object?>[],
      }),
    });
    final repository = MemoryTripRepository();
    final value = TripController(repository: repository);
    await value.load();
    expect(value.trip!.name, 'Legacy trip');
    expect(value.trip!.createdAtMs, greaterThan(0));
    expect((await repository.loadCurrent())!.id, 'legacy-trip');
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('splitcrew.trip.v1'), isNull);
  });

  test('adds expense and calculates settlement', () async {
    final value = controller();
    await value.load();
    await value.createTrip(name: 'Trip', ownerName: 'Lam');
    await value.addMember('Hoang');
    final members = value.trip!.members;
    final total = const Money(minorUnits: 100000, currencyCode: 'VND');
    final allocations = SplitEngine.equal(total: total, memberIds: members.map((m) => m.id));
    await value.addExpense(
      title: 'Lunch',
      totalMinor: total.minorUnits,
      payers: [ExpensePayer(memberId: members.first.id, amount: total)],
      allocations: allocations,
    );
    expect(value.trip!.expenses, hasLength(1));
    expect(value.settlements, hasLength(1));
    expect(value.settlements.single.amount.minorUnits, 50000);
  });

  test('renames trip and member while incrementing versions', () async {
    final value = controller();
    await value.load();
    await value.createTrip(name: 'Trip', ownerName: 'Lam');
    await value.addMember('Hoang');
    final initialTripVersion = value.trip!.version;
    final member = value.trip!.members.last;
    await value.renameTrip('Da Nang 2026');
    await value.renameMember(member.id, 'Hoang Nguyen');
    expect(value.trip!.name, 'Da Nang 2026');
    expect(value.memberName(member.id), 'Hoang Nguyen');
    expect(value.trip!.version, greaterThan(initialTripVersion));
  });

  test('removes an unreferenced non-owner member', () async {
    final value = controller();
    await value.load();
    await value.createTrip(name: 'Trip', ownerName: 'Lam');
    await value.addMember('Hoang');
    final memberId = value.trip!.members.last.id;
    await value.removeMember(memberId);
    expect(value.trip!.members, hasLength(1));
  });

  test('rejects removing a member referenced by an expense', () async {
    final value = controller();
    await value.load();
    await value.createTrip(name: 'Trip', ownerName: 'Lam');
    await value.addMember('Hoang');
    final members = value.trip!.members;
    final total = const Money(minorUnits: 100000, currencyCode: 'VND');
    await value.addExpense(
      title: 'Lunch',
      totalMinor: total.minorUnits,
      payers: [ExpensePayer(memberId: members.first.id, amount: total)],
      allocations: SplitEngine.equal(total: total, memberIds: members.map((m) => m.id)),
    );
    expect(value.removeMember(members.last.id), throwsArgumentError);
  });

  test('updates an expense and recalculates balances', () async {
    final value = controller();
    await value.load();
    await value.createTrip(name: 'Trip', ownerName: 'Lam');
    await value.addMember('Hoang');
    final members = value.trip!.members;
    const firstTotal = Money(minorUnits: 100000, currencyCode: 'VND');
    await value.addExpense(
      title: 'Lunch',
      totalMinor: firstTotal.minorUnits,
      payers: [ExpensePayer(memberId: members.first.id, amount: firstTotal)],
      allocations: SplitEngine.equal(total: firstTotal, memberIds: members.map((m) => m.id)),
    );
    final expense = value.trip!.expenses.single;
    const secondTotal = Money(minorUnits: 200000, currencyCode: 'VND');
    await value.updateExpense(
      expenseId: expense.id,
      title: 'Dinner',
      totalMinor: secondTotal.minorUnits,
      payers: [ExpensePayer(memberId: members.first.id, amount: secondTotal)],
      allocations: SplitEngine.equal(total: secondTotal, memberIds: members.map((m) => m.id)),
    );
    expect(value.trip!.expenses.single.title, 'Dinner');
    expect(value.trip!.expenses.single.version, 1);
    expect(value.settlements.single.amount.minorUnits, 100000);
  });
}
