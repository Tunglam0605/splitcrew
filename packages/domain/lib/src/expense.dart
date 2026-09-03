import 'money.dart';

final class ExpensePayer {
  const ExpensePayer({required this.memberId, required this.amount})
      : assert(memberId != '');

  final String memberId;
  final Money amount;
}

final class ExpenseAllocation {
  const ExpenseAllocation({required this.memberId, required this.amount})
      : assert(memberId != '');

  final String memberId;
  final Money amount;
}

final class Expense {
  Expense({
    required this.id,
    required this.tripId,
    required this.title,
    required this.total,
    required List<ExpensePayer> payers,
    required List<ExpenseAllocation> allocations,
    required this.createdByMemberId,
    this.version = 0,
  })  : payers = List.unmodifiable(payers),
        allocations = List.unmodifiable(allocations) {
    _validate();
  }

  final String id;
  final String tripId;
  final String title;
  final Money total;
  final List<ExpensePayer> payers;
  final List<ExpenseAllocation> allocations;
  final String createdByMemberId;
  final int version;

  void _validate() {
    if (id.isEmpty || tripId.isEmpty || title.trim().isEmpty) {
      throw ArgumentError('Expense identity, trip and title are required.');
    }
    if (createdByMemberId.isEmpty) {
      throw ArgumentError('createdByMemberId is required.');
    }
    if (version < 0) {
      throw ArgumentError.value(version, 'version', 'must be >= 0');
    }
    if (total.minorUnits < 0) {
      throw ArgumentError.value(total, 'total', 'must not be negative');
    }
    if (payers.isEmpty) {
      throw ArgumentError('At least one payer is required.');
    }
    if (allocations.isEmpty) {
      throw ArgumentError('At least one allocation is required.');
    }

    final payerMemberIds = <String>{};
    var payerSum = Money.zero(total.currencyCode);
    for (final payer in payers) {
      if (!payerMemberIds.add(payer.memberId)) {
        throw ArgumentError('Duplicate payer: ${payer.memberId}');
      }
      _requireCurrency(payer.amount);
      if (payer.amount.minorUnits < 0) {
        throw ArgumentError('Payer amount must not be negative.');
      }
      payerSum = payerSum + payer.amount;
    }

    final allocationMemberIds = <String>{};
    var allocationSum = Money.zero(total.currencyCode);
    for (final allocation in allocations) {
      if (!allocationMemberIds.add(allocation.memberId)) {
        throw ArgumentError('Duplicate allocation: ${allocation.memberId}');
      }
      _requireCurrency(allocation.amount);
      if (allocation.amount.minorUnits < 0) {
        throw ArgumentError('Allocation amount must not be negative.');
      }
      allocationSum = allocationSum + allocation.amount;
    }

    if (payerSum != total) {
      throw ArgumentError(
        'Money conservation failed: payer total $payerSum != expense $total',
      );
    }
    if (allocationSum != total) {
      throw ArgumentError(
        'Money conservation failed: allocation total $allocationSum != expense $total',
      );
    }
  }

  void _requireCurrency(Money value) {
    if (value.currencyCode != total.currencyCode) {
      throw ArgumentError(
        'Currency mismatch: ${value.currencyCode} != ${total.currencyCode}',
      );
    }
  }
}
