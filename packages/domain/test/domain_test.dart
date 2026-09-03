import 'package:splitcrew_domain/splitcrew_domain.dart';
import 'package:test/test.dart';

void main() {
  group('Money', () {
    test('adds values with the same currency', () {
      const a = Money(minorUnits: 100, currencyCode: 'VND');
      const b = Money(minorUnits: 250, currencyCode: 'VND');

      expect(a + b, const Money(minorUnits: 350, currencyCode: 'VND'));
    });

    test('rejects arithmetic across currencies', () {
      const vnd = Money(minorUnits: 100, currencyCode: 'VND');
      const usd = Money(minorUnits: 100, currencyCode: 'USD');

      expect(() => vnd + usd, throwsArgumentError);
    });
  });

  group('Expense', () {
    test('accepts multiple payers when money is conserved', () {
      final expense = Expense(
        id: 'expense-1',
        tripId: 'trip-1',
        title: 'Dinner',
        total: const Money(minorUnits: 1000000, currencyCode: 'VND'),
        payers: const [
          ExpensePayer(
            memberId: 'lam',
            amount: Money(minorUnits: 600000, currencyCode: 'VND'),
          ),
          ExpensePayer(
            memberId: 'hoang',
            amount: Money(minorUnits: 400000, currencyCode: 'VND'),
          ),
        ],
        allocations: const [
          ExpenseAllocation(
            memberId: 'lam',
            amount: Money(minorUnits: 250000, currencyCode: 'VND'),
          ),
          ExpenseAllocation(
            memberId: 'hoang',
            amount: Money(minorUnits: 350000, currencyCode: 'VND'),
          ),
          ExpenseAllocation(
            memberId: 'thanh',
            amount: Money(minorUnits: 400000, currencyCode: 'VND'),
          ),
        ],
        createdByMemberId: 'lam',
      );

      expect(expense.payers, hasLength(2));
      expect(expense.allocations, hasLength(3));
    });

    test('rejects payer totals that do not equal the expense total', () {
      expect(
        () => Expense(
          id: 'expense-1',
          tripId: 'trip-1',
          title: 'Taxi',
          total: const Money(minorUnits: 100000, currencyCode: 'VND'),
          payers: const [
            ExpensePayer(
              memberId: 'lam',
              amount: Money(minorUnits: 90000, currencyCode: 'VND'),
            ),
          ],
          allocations: const [
            ExpenseAllocation(
              memberId: 'lam',
              amount: Money(minorUnits: 100000, currencyCode: 'VND'),
            ),
          ],
          createdByMemberId: 'lam',
        ),
        throwsArgumentError,
      );
    });

    test('rejects allocation totals that do not equal the expense total', () {
      expect(
        () => Expense(
          id: 'expense-1',
          tripId: 'trip-1',
          title: 'Coffee',
          total: const Money(minorUnits: 120000, currencyCode: 'VND'),
          payers: const [
            ExpensePayer(
              memberId: 'lam',
              amount: Money(minorUnits: 120000, currencyCode: 'VND'),
            ),
          ],
          allocations: const [
            ExpenseAllocation(
              memberId: 'lam',
              amount: Money(minorUnits: 60000, currencyCode: 'VND'),
            ),
            ExpenseAllocation(
              memberId: 'hoang',
              amount: Money(minorUnits: 50000, currencyCode: 'VND'),
            ),
          ],
          createdByMemberId: 'lam',
        ),
        throwsArgumentError,
      );
    });
  });
}
