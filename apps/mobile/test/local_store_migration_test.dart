import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:splitcrew_mobile/src/local_store.dart';
import 'package:splitcrew_mobile/src/stored_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String databasePath;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    databasePath = p.join(await getDatabasesPath(), 'splitcrew.db');
  });

  setUp(() async {
    await deleteDatabase(databasePath);
  });

  tearDown(() async {
    await deleteDatabase(databasePath);
  });

  test('schema v3 upgrades to v4 and persists settlement acknowledgement history', () async {
    final legacy = await openDatabase(
      databasePath,
      version: 3,
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
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
        await db.execute('''
CREATE TABLE payment_accounts (
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
        await db.execute('''
CREATE TABLE receipt_assets (
  id TEXT PRIMARY KEY,
  expense_id TEXT NOT NULL,
  local_path TEXT NOT NULL,
  sha256 TEXT NOT NULL,
  original_name TEXT NOT NULL,
  mime_type TEXT NOT NULL,
  size_bytes INTEGER NOT NULL,
  created_at_ms INTEGER NOT NULL,
  version INTEGER NOT NULL,
  FOREIGN KEY(expense_id) REFERENCES expenses(id) ON DELETE CASCADE
)
''');
      },
    );
    await legacy.insert('trips', {
      'id': 'trip-1',
      'name': 'Migrated crew',
      'currency_code': 'VND',
      'created_at_ms': 10,
      'updated_at_ms': 10,
      'version': 3,
    });
    await legacy.insert('members', {
      'id': 'owner',
      'trip_id': 'trip-1',
      'name': 'Owner',
      'is_owner': 1,
      'created_at_ms': 10,
      'updated_at_ms': 10,
      'version': 0,
    });
    await legacy.insert('members', {
      'id': 'member',
      'trip_id': 'trip-1',
      'name': 'An',
      'is_owner': 0,
      'created_at_ms': 11,
      'updated_at_ms': 11,
      'version': 0,
    });
    expect(await legacy.getVersion(), 3);
    await legacy.close();

    final repository = SqliteTripRepository();
    final migrated = await repository.loadCurrent();
    expect(migrated, isNotNull);
    expect(migrated!.name, 'Migrated crew');
    expect(migrated.members.map((member) => member.name), containsAll(['Owner', 'An']));
    expect(migrated.settlementAcknowledgements, isEmpty);

    final trip = migrated.copyWith(
      settlementAcknowledgements: const [
        StoredSettlementAcknowledgement(
          id: 'ack-1',
          fromMemberId: 'member',
          toMemberId: 'owner',
          amountMinor: 60000,
          confirmedByMemberId: 'member',
          createdAtMs: 123,
        ),
      ],
      version: 4,
    );

    await repository.save(trip);
    final reloaded = await repository.loadCurrent();

    expect(reloaded, isNotNull);
    expect(reloaded!.members, hasLength(2));
    expect(reloaded.settlementAcknowledgements, hasLength(1));
    expect(reloaded.settlementAcknowledgements.single.id, 'ack-1');
    await repository.close();

    final upgraded = await openDatabase(databasePath);
    expect(await upgraded.getVersion(), 4);
    final tables = await upgraded.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='settlement_acknowledgements'",
    );
    expect(tables, isNotEmpty);
    await upgraded.close();
  });
}
