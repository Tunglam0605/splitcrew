import 'package:splitcrew_domain/splitcrew_domain.dart';
import 'package:splitcrew_split_engine/splitcrew_split_engine.dart';
import 'package:test/test.dart';

void main() {
  const total = Money(minorUnits: 100, currencyCode: 'VND');

  test('equal split conserves uneven totals deterministically', () {
    final result = SplitEngine.equal(total: total, memberIds: ['c', 'a', 'b']);
    expect(result.map((e) => e.memberId), ['a', 'b', 'c']);
    expect(result.map((e) => e.amount.minorUnits), [34, 33, 33]);
    expect(result.fold<int>(0, (s, e) => s + e.amount.minorUnits), 100);
  });

  test('exact split rejects mismatched totals', () {
    expect(
      () => SplitEngine.exact(
        total: total,
        amounts: const {
          'a': Money(minorUnits: 50, currencyCode: 'VND'),
          'b': Money(minorUnits: 49, currencyCode: 'VND'),
        },
      ),
      throwsArgumentError,
    );
  });

  test('percentage split uses basis points without floating point', () {
    final result = SplitEngine.percentages(
      total: const Money(minorUnits: 999, currencyCode: 'VND'),
      basisPoints: const {'a': 3333, 'b': 3333, 'c': 3334},
    );
    expect(result.fold<int>(0, (s, e) => s + e.amount.minorUnits), 999);
  });

  test('zero-percent member never receives rounding remainder', () {
    final result = SplitEngine.percentages(
      total: const Money(minorUnits: 1, currencyCode: 'VND'),
      basisPoints: const {'a': 0, 'b': 5000, 'c': 5000},
    );
    expect(result.firstWhere((e) => e.memberId == 'a').amount.minorUnits, 0);
    expect(result.fold<int>(0, (s, e) => s + e.amount.minorUnits), 1);
  });

  test('share split conserves total using largest remainder', () {
    final result = SplitEngine.shares(
      total: const Money(minorUnits: 101, currencyCode: 'VND'),
      shares: const {'a': 1, 'b': 2},
    );
    expect(result.fold<int>(0, (s, e) => s + e.amount.minorUnits), 101);
    expect(result.map((e) => e.amount.minorUnits), [34, 67]);
  });

  test('per-item split aggregates members across items', () {
    final result = SplitEngine.perItem(
      items: [
        SplitItem(
          amount: const Money(minorUnits: 90, currencyCode: 'VND'),
          memberIds: ['a', 'b', 'c'],
        ),
        SplitItem(
          amount: const Money(minorUnits: 20, currencyCode: 'VND'),
          memberIds: ['a'],
        ),
      ],
    );
    expect(result.map((e) => e.memberId), ['a', 'b', 'c']);
    expect(result.map((e) => e.amount.minorUnits), [50, 30, 30]);
  });
}
