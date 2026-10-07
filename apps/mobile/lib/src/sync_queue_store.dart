import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:splitcrew_sync_protocol/splitcrew_sync_protocol.dart';

enum PendingSyncState { queued, blocked }

final class PendingSyncEntry {
  const PendingSyncEntry({
    required this.operation,
    required this.state,
    required this.attemptCount,
    required this.updatedAtEpochMs,
    this.enqueueSequence,
    this.lastError,
  });

  final SyncOperation operation;
  final PendingSyncState state;
  final int attemptCount;
  final int updatedAtEpochMs;
  final int? enqueueSequence;
  final String? lastError;

  PendingSyncEntry copyWith({
    SyncOperation? operation,
    PendingSyncState? state,
    int? attemptCount,
    int? updatedAtEpochMs,
    int? enqueueSequence,
    String? lastError,
    bool clearLastError = false,
  }) {
    return PendingSyncEntry(
      operation: operation ?? this.operation,
      state: state ?? this.state,
      attemptCount: attemptCount ?? this.attemptCount,
      updatedAtEpochMs: updatedAtEpochMs ?? this.updatedAtEpochMs,
      enqueueSequence: enqueueSequence ?? this.enqueueSequence,
      lastError: clearLastError ? null : lastError ?? this.lastError,
    );
  }
}

abstract interface class PendingSyncQueueStore {
  Future<List<PendingSyncEntry>> loadAll();
  Future<void> upsert(PendingSyncEntry entry);
  Future<void> delete(String operationId);
  Future<void> clearForTrip(String tripId);
}

final class SqlitePendingSyncQueueStore implements PendingSyncQueueStore {
  Database? _database;

  Future<Database> _open() async {
    final existing = _database;
    if (existing != null) return existing;
    final root = await getDatabasesPath();
    final database = await openDatabase(
      p.join(root, 'splitcrew-sync-queue.db'),
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
CREATE TABLE pending_sync_operations (
  operation_id TEXT PRIMARY KEY,
  trip_id TEXT NOT NULL,
  actor_member_id TEXT NOT NULL,
  operation_json TEXT NOT NULL,
  state TEXT NOT NULL,
  attempt_count INTEGER NOT NULL,
  last_error TEXT,
  updated_at_ms INTEGER NOT NULL,
  enqueue_sequence INTEGER NOT NULL
)
''');
        await db.execute(
          'CREATE INDEX idx_pending_sync_trip_sequence '
          'ON pending_sync_operations(trip_id, enqueue_sequence)',
        );
        await db.execute('''
CREATE TABLE pending_sync_metadata (
  key TEXT PRIMARY KEY,
  int_value INTEGER NOT NULL
)
''');
        await db.insert(
          'pending_sync_metadata',
          const {'key': 'next_enqueue_sequence', 'int_value': 1},
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE pending_sync_operations ADD COLUMN enqueue_sequence INTEGER',
          );
          final rows = await db.query(
            'pending_sync_operations',
            columns: ['operation_id'],
            orderBy: 'updated_at_ms ASC, operation_id ASC',
          );
          var sequence = 0;
          for (final row in rows) {
            sequence += 1;
            await db.update(
              'pending_sync_operations',
              {'enqueue_sequence': sequence},
              where: 'operation_id = ?',
              whereArgs: [row['operation_id']],
            );
          }
          await db.execute(
            'CREATE INDEX idx_pending_sync_trip_sequence '
            'ON pending_sync_operations(trip_id, enqueue_sequence)',
          );
          await db.execute('''
CREATE TABLE pending_sync_metadata (
  key TEXT PRIMARY KEY,
  int_value INTEGER NOT NULL
)
''');
          await db.insert(
            'pending_sync_metadata',
            {
              'key': 'next_enqueue_sequence',
              'int_value': sequence + 1,
            },
          );
        }
      },
    );
    _database = database;
    return database;
  }

  @override
  Future<List<PendingSyncEntry>> loadAll() async {
    final db = await _open();
    final rows = await db.query(
      'pending_sync_operations',
      orderBy: 'enqueue_sequence ASC, operation_id ASC',
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  @override
  Future<void> upsert(PendingSyncEntry entry) async {
    final db = await _open();
    await db.transaction((txn) async {
      final existing = await txn.query(
        'pending_sync_operations',
        columns: ['enqueue_sequence'],
        where: 'operation_id = ?',
        whereArgs: [entry.operation.operationId],
        limit: 1,
      );

      int sequence;
      if (entry.enqueueSequence != null) {
        sequence = entry.enqueueSequence!;
        await _advanceNextSequencePast(txn, sequence);
      } else if (existing.isNotEmpty) {
        sequence = existing.single['enqueue_sequence'] as int;
      } else {
        final metadata = await txn.query(
          'pending_sync_metadata',
          columns: ['int_value'],
          where: 'key = ?',
          whereArgs: ['next_enqueue_sequence'],
          limit: 1,
        );
        if (metadata.isEmpty) {
          throw StateError('Pending sync queue metadata is missing.');
        }
        sequence = metadata.single['int_value'] as int;
        await txn.update(
          'pending_sync_metadata',
          {'int_value': sequence + 1},
          where: 'key = ?',
          whereArgs: ['next_enqueue_sequence'],
        );
      }

      await txn.insert(
        'pending_sync_operations',
        {
          'operation_id': entry.operation.operationId,
          'trip_id': entry.operation.tripId,
          'actor_member_id': entry.operation.actorMemberId,
          'operation_json': jsonEncode(entry.operation.toJson()),
          'state': entry.state.name,
          'attempt_count': entry.attemptCount,
          'last_error': entry.lastError,
          'updated_at_ms': entry.updatedAtEpochMs,
          'enqueue_sequence': sequence,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<void> _advanceNextSequencePast(
    Transaction txn,
    int sequence,
  ) async {
    final metadata = await txn.query(
      'pending_sync_metadata',
      columns: ['int_value'],
      where: 'key = ?',
      whereArgs: ['next_enqueue_sequence'],
      limit: 1,
    );
    if (metadata.isEmpty) {
      throw StateError('Pending sync queue metadata is missing.');
    }
    final current = metadata.single['int_value'] as int;
    if (current <= sequence) {
      await txn.update(
        'pending_sync_metadata',
        {'int_value': sequence + 1},
        where: 'key = ?',
        whereArgs: ['next_enqueue_sequence'],
      );
    }
  }

  @override
  Future<void> delete(String operationId) async {
    final db = await _open();
    await db.delete(
      'pending_sync_operations',
      where: 'operation_id = ?',
      whereArgs: [operationId],
    );
  }

  @override
  Future<void> clearForTrip(String tripId) async {
    final db = await _open();
    await db.delete(
      'pending_sync_operations',
      where: 'trip_id = ?',
      whereArgs: [tripId],
    );
  }

  Future<void> close() async {
    final db = _database;
    _database = null;
    if (db != null) await db.close();
  }

  PendingSyncEntry _fromRow(Map<String, Object?> row) {
    final decoded = jsonDecode(row['operation_json'] as String);
    if (decoded is! Map) throw const FormatException('Invalid queued sync operation JSON.');
    final sequence = row['enqueue_sequence'];
    if (sequence is! int || sequence <= 0) {
      throw const FormatException('Invalid pending sync enqueue sequence.');
    }
    return PendingSyncEntry(
      operation: SyncOperation.fromJson(Map<String, dynamic>.from(decoded)),
      state: PendingSyncState.values.byName(row['state'] as String),
      attemptCount: row['attempt_count'] as int,
      lastError: row['last_error'] as String?,
      updatedAtEpochMs: row['updated_at_ms'] as int,
      enqueueSequence: sequence,
    );
  }
}

final class MemoryPendingSyncQueueStore implements PendingSyncQueueStore {
  final Map<String, PendingSyncEntry> _entries = {};
  int _nextSequence = 1;

  @override
  Future<List<PendingSyncEntry>> loadAll() async {
    final values = _entries.values.toList()
      ..sort((a, b) {
        final sequence = (a.enqueueSequence ?? 0).compareTo(b.enqueueSequence ?? 0);
        if (sequence != 0) return sequence;
        return a.operation.operationId.compareTo(b.operation.operationId);
      });
    return List.unmodifiable(values);
  }

  @override
  Future<void> upsert(PendingSyncEntry entry) async {
    final existing = _entries[entry.operation.operationId];
    final sequence = entry.enqueueSequence ?? existing?.enqueueSequence ?? _nextSequence++;
    if (sequence >= _nextSequence) _nextSequence = sequence + 1;
    _entries[entry.operation.operationId] = entry.copyWith(enqueueSequence: sequence);
  }

  @override
  Future<void> delete(String operationId) async {
    _entries.remove(operationId);
  }

  @override
  Future<void> clearForTrip(String tripId) async {
    _entries.removeWhere((key, value) => value.operation.tripId == tripId);
  }
}
