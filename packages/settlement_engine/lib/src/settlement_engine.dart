import 'package:splitcrew_domain/splitcrew_domain.dart';

final class MemberBalance {
  const MemberBalance({required this.memberId, required this.balance});

  final String memberId;
  final Money balance;
}

final class SettlementTransfer {
  const SettlementTransfer({
    required this.fromMemberId,
    required this.toMemberId,
    required this.amount,
  });

  final String fromMemberId;
  final String toMemberId;
  final Money amount;
}

final class SettlementEngine {
  const SettlementEngine._();

  static List<MemberBalance> calculateBalances({
    required Iterable<Expense> expenses,
    required Iterable<String> memberIds,
    required String currencyCode,
  }) {
    if (currencyCode.length != 3) {
      throw ArgumentError('currencyCode must contain three characters.');
    }
    final ids = memberIds.toSet().toList()..sort();
    if (ids.any((id) => id.trim().isEmpty)) {
      throw ArgumentError('Member IDs must not be empty.');
    }
    final units = <String, int>{for (final id in ids) id: 0};

    for (final expense in expenses) {
      if (expense.total.currencyCode != currencyCode) {
        throw ArgumentError('All expenses must use $currencyCode.');
      }
      for (final payer in expense.payers) {
        units.update(
          payer.memberId,
          (value) => value + payer.amount.minorUnits,
          ifAbsent: () => payer.amount.minorUnits,
        );
      }
      for (final allocation in expense.allocations) {
        units.update(
          allocation.memberId,
          (value) => value - allocation.amount.minorUnits,
          ifAbsent: () => -allocation.amount.minorUnits,
        );
      }
    }

    final total = units.values.fold<int>(0, (a, b) => a + b);
    if (total != 0) {
      throw StateError('Balance conservation failed: net balance is $total.');
    }

    final allIds = units.keys.toList()..sort();
    return List.unmodifiable([
      for (final id in allIds)
        MemberBalance(
          memberId: id,
          balance: Money(minorUnits: units[id]!, currencyCode: currencyCode),
        ),
    ]);
  }

  static List<SettlementTransfer> settleBalances(
    Iterable<MemberBalance> balances,
  ) {
    final list = List<MemberBalance>.from(balances);
    if (list.isEmpty) return const [];
    final currency = list.first.balance.currencyCode;
    if (list.any((b) => b.balance.currencyCode != currency)) {
      throw ArgumentError('All balances must use the same currency.');
    }
    final net = list.fold<int>(0, (sum, b) => sum + b.balance.minorUnits);
    if (net != 0) {
      throw ArgumentError('Balances must sum to zero before settlement.');
    }

    final creditors = [
      for (final b in list)
        if (b.balance.minorUnits > 0)
          _MutableBalance(b.memberId, b.balance.minorUnits),
    ]
      ..sort(_creditorSort);
    final debtors = [
      for (final b in list)
        if (b.balance.minorUnits < 0)
          _MutableBalance(b.memberId, -b.balance.minorUnits),
    ]
      ..sort(_debtorSort);

    final transfers = <SettlementTransfer>[];
    var ci = 0;
    var di = 0;
    while (ci < creditors.length && di < debtors.length) {
      final creditor = creditors[ci];
      final debtor = debtors[di];
      final amount = creditor.units < debtor.units ? creditor.units : debtor.units;
      if (amount > 0) {
        transfers.add(
          SettlementTransfer(
            fromMemberId: debtor.memberId,
            toMemberId: creditor.memberId,
            amount: Money(minorUnits: amount, currencyCode: currency),
          ),
        );
        creditor.units -= amount;
        debtor.units -= amount;
      }
      if (creditor.units == 0) ci++;
      if (debtor.units == 0) di++;
    }

    if (ci != creditors.length || di != debtors.length) {
      throw StateError('Settlement did not fully clear all balances.');
    }
    return List.unmodifiable(transfers);
  }

  static List<SettlementTransfer> calculateSettlements({
    required Iterable<Expense> expenses,
    required Iterable<String> memberIds,
    required String currencyCode,
  }) {
    return settleBalances(
      calculateBalances(
        expenses: expenses,
        memberIds: memberIds,
        currencyCode: currencyCode,
      ),
    );
  }

  static int _creditorSort(_MutableBalance a, _MutableBalance b) {
    final byAmount = b.units.compareTo(a.units);
    return byAmount != 0 ? byAmount : a.memberId.compareTo(b.memberId);
  }

  static int _debtorSort(_MutableBalance a, _MutableBalance b) {
    final byAmount = b.units.compareTo(a.units);
    return byAmount != 0 ? byAmount : a.memberId.compareTo(b.memberId);
  }
}

final class _MutableBalance {
  _MutableBalance(this.memberId, this.units);

  final String memberId;
  int units;
}
