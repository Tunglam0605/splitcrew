import 'package:splitcrew_domain/splitcrew_domain.dart';
import 'package:splitcrew_settlement_engine/splitcrew_settlement_engine.dart';
import 'package:test/test.dart';

Expense _expense({
  required String id,
  required List<ExpensePayer> payers,
  required List<ExpenseAllocation> allocations,
  required int total,
}) {
  return Expense(
    id: id,
    tripId: 'trip',
    title: id,
    total: Money(minorUnits: total, currencyCode: 'VND'),
    payers: payers,
    allocations: allocations,
    createdByMemberId: 'a',
  );
}

void main() {
  test('calculates net balances from paid minus consumed amounts', () {
    final expense = _expense(
      id: 'dinner',
      total: 300,
      payers: const [
        ExpensePayer(memberId: 'a', amount: Money(minorUnits: 300, currencyCode: 'VND')),
      ],
      allocations: const [
        ExpenseAllocation(memberId: 'a', amount: Money(minorUnits: 100, currencyCode: 'VND')),
        ExpenseAllocation(memberId: 'b', amount: Money(minorUnits: 100, currencyCode: 'VND')),
        ExpenseAllocation(memberId: 'c', amount: Money(minorUnits: 100, currencyCode: 'VND')),
      ],
    );
    final balances = SettlementEngine.calculateBalances(
      expenses: [expense],
      memberIds: const ['a', 'b', 'c'],
      currencyCode: 'VND',
    );
    expect(balances.map((b) => b.balance.minorUnits), [200, -100, -100]);
  });

  test('generates deterministic transfers that clear balances', () {
    const balances = [
      MemberBalance(memberId: 'a', balance: Money(minorUnits: 200, currencyCode: 'VND')),
      MemberBalance(memberId: 'b', balance: Money(minorUnits: -50, currencyCode: 'VND')),
      MemberBalance(memberId: 'c', balance: Money(minorUnits: -150, currencyCode: 'VND')),
    ];
    final transfers = SettlementEngine.settleBalances(balances);
    expect(transfers, hasLength(2));
    expect(transfers[0].fromMemberId, 'c');
    expect(transfers[0].toMemberId, 'a');
    expect(transfers[0].amount.minorUnits, 150);
    expect(transfers[1].fromMemberId, 'b');
    expect(transfers[1].amount.minorUnits, 50);
  });

  test('already balanced group produces no transfers', () {
    const balances = [
      MemberBalance(memberId: 'a', balance: Money(minorUnits: 0, currencyCode: 'VND')),
      MemberBalance(memberId: 'b', balance: Money(minorUnits: 0, currencyCode: 'VND')),
    ];
    expect(SettlementEngine.settleBalances(balances), isEmpty);
  });
}
