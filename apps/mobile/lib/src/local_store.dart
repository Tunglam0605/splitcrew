import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:splitcrew_domain/splitcrew_domain.dart';

import 'stored_models.dart';

abstract interface class TripRepository {
  Future<StoredTrip?> loadCurrent();
  Future<void> save(StoredTrip trip);
  Future<void> deleteCurrent();
}

final class MemoryTripRepository implements TripRepository {
  StoredTrip? _trip;

  @override
  Future<StoredTrip?> loadCurrent() async => _trip;

  @override
  Future<void> save(StoredTrip trip) async {
    _trip = trip;
  }

  @override
  Future<void> deleteCurrent() async {
    _trip = null;
  }
}

final class SqliteTripRepository implements TripRepository {
  static const schemaVersion = 2;

  Database? _database;

  Future<Database> _open() async {
    final existing = _database;
    if (existing != null) return existing;
    final root = await getDatabasesPath();
    final database = await openDatabase(
      p.join(root, 'splitcrew.db'),
      version: schemaVersion,
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        await _createCoreTables(db);
        await _createPaymentAccountsTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createPaymentAccountsTable(db);
        }
      },
    );
    _database = database;
    return database;
  }

  Future<void> _createCoreTables(Database db) async {
    await db.execute('''
CREATE TABLE trips (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  currency_code TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  version INTEGER NOT NULL
)
''');
    await db.execute('''
CREATE TABLE members (
  id TEXT PRIMARY KEY,
  trip_id TEXT NOT NULL,
  name TEXT NOT NULL,
  is_owner INTEGER NOT NULL,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  version INTEGER NOT NULL,
  FOREIGN KEY(trip_id) REFERENCES trips(id) ON DELETE CASCADE
)
''');
    await db.execute('''
CREATE TABLE expenses (
  id TEXT PRIMARY KEY,
  trip_id TEXT NOT NULL,
  title TEXT NOT NULL,
  total_minor INTEGER NOT NULL,
  created_by_member_id TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  version INTEGER NOT NULL,
  FOREIGN KEY(trip_id) REFERENCES trips(id) ON DELETE CASCADE
)
''');
    await db.execute('''
CREATE TABLE expense_payers (
  expense_id TEXT NOT NULL,
  member_id TEXT NOT NULL,
  amount_minor INTEGER NOT NULL,
  PRIMARY KEY(expense_id, member_id),
  FOREIGN KEY(expense_id) REFERENCES expenses(id) ON DELETE CASCADE,
  FOREIGN KEY(member_id) REFERENCES members(id)
)
''');
    await db.execute('''
CREATE TABLE expense_allocations (
  expense_id TEXT NOT NULL,
  member_id TEXT NOT NULL,
  amount_minor INTEGER NOT NULL,
  PRIMARY KEY(expense_id, member_id),
  FOREIGN KEY(expense_id) REFERENCES expenses(id) ON DELETE CASCADE,
  FOREIGN KEY(member_id) REFERENCES members(id)
)
''');
    await db.execute('CREATE INDEX idx_members_trip ON members(trip_id)');
    await db.execute('CREATE INDEX idx_expenses_trip ON expenses(trip_id)');
  }

  Future<void> _createPaymentAccountsTable(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS payment_accounts (
  id TEXT PRIMARY KEY,
  member_id TEXT NOT NULL UNIQUE,
  provider TEXT NOT NULL,
  holder_name TEXT NOT NULL,
  routing_identifier TEXT NOT NULL,
  account_identifier TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  version INTEGER NOT NULL,
  FOREIGN KEY(member_id) REFERENCES members(id) ON DELETE CASCADE
)
''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_payment_accounts_member ON payment_accounts(member_id)');
  }

  @override
  Future<StoredTrip?> loadCurrent() async {
    final db = await _open();
    final tripRows = await db.query('trips', orderBy: 'updated_at_ms DESC', limit: 1);
    if (tripRows.isEmpty) return null;
    final row = tripRows.single;
    final tripId = row['id'] as String;
    final memberRows = await db.query(
      'members',
      where: 'trip_id = ?',
      whereArgs: [tripId],
      orderBy: 'created_at_ms ASC',
    );
    final expenseRows = await db.query(
      'expenses',
      where: 'trip_id = ?',
      whereArgs: [tripId],
      orderBy: 'created_at_ms ASC',
    );
    final paymentRows = await db.rawQuery(
      '''
SELECT p.*
FROM payment_accounts p
INNER JOIN members m ON m.id = p.member_id
WHERE m.trip_id = ?
ORDER BY p.created_at_ms ASC
''',
      [tripId],
    );

    final members = [
      for (final member in memberRows)
        StoredMember(
          id: member['id'] as String,
          name: member['name'] as String,
          isOwner: (member['is_owner'] as int) == 1,
          createdAtMs: member['created_at_ms'] as int,
          updatedAtMs: member['updated_at_ms'] as int,
          version: member['version'] as int,
        ),
    ];

    final paymentAccounts = [
      for (final payment in paymentRows)
        StoredPaymentAccount(
          id: payment['id'] as String,
          memberId: payment['member_id'] as String,
          provider: PaymentAccountProvider.values.byName(payment['provider'] as String),
          holderName: payment['holder_name'] as String,
          routingIdentifier: payment['routing_identifier'] as String,
          accountIdentifier: payment['account_identifier'] as String,
          createdAtMs: payment['created_at_ms'] as int,
          updatedAtMs: payment['updated_at_ms'] as int,
          version: payment['version'] as int,
        ),
    ];

    final expenses = <StoredExpense>[];
    for (final expense in expenseRows) {
      final expenseId = expense['id'] as String;
      final payerRows = await db.query('expense_payers', where: 'expense_id = ?', whereArgs: [expenseId]);
      final allocationRows = await db.query('expense_allocations', where: 'expense_id = ?', whereArgs: [expenseId]);
      expenses.add(
        StoredExpense(
          id: expenseId,
          title: expense['title'] as String,
          totalMinor: expense['total_minor'] as int,
          payerMinorByMember: {
            for (final payer in payerRows) payer['member_id'] as String: payer['amount_minor'] as int,
          },
          allocationMinorByMember: {
            for (final allocation in allocationRows)
              allocation['member_id'] as String: allocation['amount_minor'] as int,
          },
          createdByMemberId: expense['created_by_member_id'] as String,
          createdAtMs: expense['created_at_ms'] as int,
          updatedAtMs: expense['updated_at_ms'] as int,
          version: expense['version'] as int,
        ),
      );
    }

    return StoredTrip(
      id: tripId,
      name: row['name'] as String,
      currencyCode: row['currency_code'] as String,
      members: members,
      expenses: expenses,
      paymentAccounts: paymentAccounts,
      createdAtMs: row['created_at_ms'] as int,
      updatedAtMs: row['updated_at_ms'] as int,
      version: row['version'] as int,
    );
  }

  @override
  Future<void> save(StoredTrip trip) async {
    final db = await _open();
    await db.transaction((txn) async {
      await txn.delete('expenses', where: 'trip_id = ?', whereArgs: [trip.id]);
      await txn.delete('members', where: 'trip_id = ?', whereArgs: [trip.id]);
      await txn.insert(
        'trips',
        {
          'id': trip.id,
          'name': trip.name,
          'currency_code': trip.currencyCode,
          'created_at_ms': trip.createdAtMs,
          'updated_at_ms': trip.updatedAtMs,
          'version': trip.version,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      for (final member in trip.members) {
        await txn.insert('members', {
          'id': member.id,
          'trip_id': trip.id,
          'name': member.name,
          'is_owner': member.isOwner ? 1 : 0,
          'created_at_ms': member.createdAtMs,
          'updated_at_ms': member.updatedAtMs,
          'version': member.version,
        });
      }
      for (final payment in trip.paymentAccounts) {
        await txn.insert('payment_accounts', {
          'id': payment.id,
          'member_id': payment.memberId,
          'provider': payment.provider.name,
          'holder_name': payment.holderName,
          'routing_identifier': payment.routingIdentifier,
          'account_identifier': payment.accountIdentifier,
          'created_at_ms': payment.createdAtMs,
          'updated_at_ms': payment.updatedAtMs,
          'version': payment.version,
        });
      }
      for (final expense in trip.expenses) {
        await txn.insert('expenses', {
          'id': expense.id,
          'trip_id': trip.id,
          'title': expense.title,
          'total_minor': expense.totalMinor,
          'created_by_member_id': expense.createdByMemberId,
          'created_at_ms': expense.createdAtMs,
          'updated_at_ms': expense.updatedAtMs,
          'version': expense.version,
        });
        for (final payer in expense.payerMinorByMember.entries) {
          await txn.insert('expense_payers', {
            'expense_id': expense.id,
            'member_id': payer.key,
            'amount_minor': payer.value,
          });
        }
        for (final allocation in expense.allocationMinorByMember.entries) {
          await txn.insert('expense_allocations', {
            'expense_id': expense.id,
            'member_id': allocation.key,
            'amount_minor': allocation.value,
          });
        }
      }
    });
  }

  @override
  Future<void> deleteCurrent() async {
    final db = await _open();
    await db.delete('trips');
  }
}
