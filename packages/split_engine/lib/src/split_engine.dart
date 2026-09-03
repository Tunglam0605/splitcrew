import 'package:splitcrew_domain/splitcrew_domain.dart';

final class SplitItem {
  SplitItem({required this.amount, required List<String> memberIds})
      : memberIds = List.unmodifiable(_normalizedIds(memberIds)) {
    if (amount.minorUnits < 0) {
      throw ArgumentError.value(amount, 'amount', 'must not be negative');
    }
  }

  final Money amount;
  final List<String> memberIds;
}

final class SplitEngine {
  const SplitEngine._();

  static List<ExpenseAllocation> equal({
    required Money total,
    required Iterable<String> memberIds,
  }) {
    final ids = _normalizedIds(memberIds);
    _requireNonNegativeTotal(total);
    if (ids.isEmpty) {
      throw ArgumentError('At least one member is required.');
    }

    final base = total.minorUnits ~/ ids.length;
    var remainder = total.minorUnits - (base * ids.length);
    return [
      for (final id in ids)
        ExpenseAllocation(
          memberId: id,
          amount: Money(
            minorUnits: base + (remainder-- > 0 ? 1 : 0),
            currencyCode: total.currencyCode,
          ),
        ),
    ];
  }

  static List<ExpenseAllocation> exact({
    required Money total,
    required Map<String, Money> amounts,
  }) {
    _requireNonNegativeTotal(total);
    if (amounts.isEmpty) {
      throw ArgumentError('At least one member amount is required.');
    }

    final ids = _normalizedIds(amounts.keys);
    var sum = Money.zero(total.currencyCode);
    final allocations = <ExpenseAllocation>[];
    for (final id in ids) {
      final amount = amounts[id]!;
      _requireSameCurrency(total, amount);
      if (amount.minorUnits < 0) {
        throw ArgumentError('Exact split amounts must not be negative.');
      }
      sum = sum + amount;
      allocations.add(ExpenseAllocation(memberId: id, amount: amount));
    }
    if (sum != total) {
      throw ArgumentError('Exact split total $sum does not equal $total.');
    }
    return List.unmodifiable(allocations);
  }

  static List<ExpenseAllocation> percentages({
    required Money total,
    required Map<String, int> basisPoints,
  }) {
    if (basisPoints.isEmpty) {
      throw ArgumentError('At least one percentage is required.');
    }
    final sum = basisPoints.values.fold<int>(0, (a, b) => a + b);
    if (sum != 10000) {
      throw ArgumentError('Percentages must sum to 100.00% (10000 basis points).');
    }
    if (basisPoints.values.any((value) => value < 0)) {
      throw ArgumentError('Percentage values must not be negative.');
    }
    return _weighted(total: total, weights: basisPoints);
  }

  static List<ExpenseAllocation> shares({
    required Money total,
    required Map<String, int> shares,
  }) {
    if (shares.isEmpty) {
      throw ArgumentError('At least one share is required.');
    }
    if (shares.values.any((value) => value <= 0)) {
      throw ArgumentError('Share weights must be positive integers.');
    }
    return _weighted(total: total, weights: shares);
  }

  static List<ExpenseAllocation> perItem({
    required Iterable<SplitItem> items,
  }) {
    final itemList = List<SplitItem>.from(items);
    if (itemList.isEmpty) {
      throw ArgumentError('At least one item is required.');
    }
    final currency = itemList.first.amount.currencyCode;
    final totals = <String, int>{};
    for (final item in itemList) {
      if (item.amount.currencyCode != currency) {
        throw ArgumentError('All item currencies must match.');
      }
      final allocations = equal(total: item.amount, memberIds: item.memberIds);
      for (final allocation in allocations) {
        totals.update(
          allocation.memberId,
          (value) => value + allocation.amount.minorUnits,
          ifAbsent: () => allocation.amount.minorUnits,
        );
      }
    }
    final ids = totals.keys.toList()..sort();
    return List.unmodifiable([
      for (final id in ids)
        ExpenseAllocation(
          memberId: id,
          amount: Money(minorUnits: totals[id]!, currencyCode: currency),
        ),
    ]);
  }

  static List<ExpenseAllocation> _weighted({
    required Money total,
    required Map<String, int> weights,
  }) {
    _requireNonNegativeTotal(total);
    final ids = _normalizedIds(weights.keys);
    final totalWeight = weights.values.fold<int>(0, (a, b) => a + b);
    if (totalWeight <= 0) {
      throw ArgumentError('Total weight must be positive.');
    }

    final units = <String, int>{};
    var assigned = 0;
    for (final id in ids) {
      final weight = weights[id]!;
      if (weight < 0) {
        throw ArgumentError('Weights must not be negative.');
      }
      final value = (total.minorUnits * weight) ~/ totalWeight;
      units[id] = value;
      assigned += value;
    }

    var remainder = total.minorUnits - assigned;
    for (final id in ids) {
      if (remainder == 0) break;
      units[id] = units[id]! + 1;
      remainder--;
    }

    return List.unmodifiable([
      for (final id in ids)
        ExpenseAllocation(
          memberId: id,
          amount: Money(minorUnits: units[id]!, currencyCode: total.currencyCode),
        ),
    ]);
  }

  static void _requireNonNegativeTotal(Money total) {
    if (total.minorUnits < 0) {
      throw ArgumentError.value(total, 'total', 'must not be negative');
    }
  }

  static void _requireSameCurrency(Money a, Money b) {
    if (a.currencyCode != b.currencyCode) {
      throw ArgumentError('Currency mismatch: ${a.currencyCode} != ${b.currencyCode}');
    }
  }
}

List<String> _normalizedIds(Iterable<String> memberIds) {
  final ids = memberIds.toSet().toList()..sort();
  if (ids.any((id) => id.trim().isEmpty)) {
    throw ArgumentError('Member IDs must not be empty.');
  }
  if (ids.length != memberIds.length) {
    throw ArgumentError('Duplicate member IDs are not allowed.');
  }
  return ids;
}
