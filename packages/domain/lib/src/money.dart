/// Immutable monetary value stored in integer minor units.
///
/// SplitCrew never uses floating-point arithmetic for persisted money or
/// final balances. For VND, [minorUnits] represents whole dong. For USD,
/// it represents cents.
final class Money implements Comparable<Money> {
  const Money({required this.minorUnits, required this.currencyCode})
      : assert(currencyCode.length == 3);

  final int minorUnits;
  final String currencyCode;

  factory Money.zero(String currencyCode) =>
      Money(minorUnits: 0, currencyCode: currencyCode);

  Money operator +(Money other) {
    _requireSameCurrency(other);
    return Money(
      minorUnits: minorUnits + other.minorUnits,
      currencyCode: currencyCode,
    );
  }

  Money operator -(Money other) {
    _requireSameCurrency(other);
    return Money(
      minorUnits: minorUnits - other.minorUnits,
      currencyCode: currencyCode,
    );
  }

  Money operator -() => Money(
        minorUnits: -minorUnits,
        currencyCode: currencyCode,
      );

  bool get isZero => minorUnits == 0;
  bool get isPositive => minorUnits > 0;
  bool get isNegative => minorUnits < 0;

  @override
  int compareTo(Money other) {
    _requireSameCurrency(other);
    return minorUnits.compareTo(other.minorUnits);
  }

  void _requireSameCurrency(Money other) {
    if (currencyCode != other.currencyCode) {
      throw ArgumentError(
        'Currency mismatch: $currencyCode != ${other.currencyCode}',
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      other is Money &&
      minorUnits == other.minorUnits &&
      currencyCode == other.currencyCode;

  @override
  int get hashCode => Object.hash(minorUnits, currencyCode);

  @override
  String toString() => '$minorUnits $currencyCode(minor)';
}
