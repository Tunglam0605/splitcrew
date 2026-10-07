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
    this.lastError,
  });

  final SyncOperation operation;
  final PendingSyncState state;
  final int attemptCount;
  final int updatedAtEpochMs;
  final String? lastError;

  PendingSyncEntry copyWith({
    SyncOperation? operation,
    PendingSyncState? state,
    int? attemptCount,
    int? updatedAtEpochMs,
    String? lastError,
    bool clearLastError = false,
  }) {
    return PendingSyncEntry(
      operation: operation ?? this.operation,
      state: state ?? this.state,
      attemptCount: attemptCount ?? this.attemptCount,
      updatedAtEpochMs: updatedAtEpochMs ?? this.updatedAtEpochMs,
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
      version: 1,
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
  updated_at_ms INTEGER NOT NULL
)
''');
        await db.execute(
          'CREATE INDEX idx_pending_sync_trip ON pending_sync_operations(trip_id, updated_at_ms)',
        );
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
      orderBy: 'updated_at_ms ASC, operation_id ASC',
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  @override
  Future<void> upsert(PendingSyncEntry entry) async {
    final db = await _open();
    await db.insert(
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
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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

  PendingSyncEntry _fromRow(Map<String, Object?> row) {
    final decoded = jsonDecode(row['operation_json'] as String);
    if (decoded is! Map) throw const FormatException('Invalid queued sync operation JSON.');
    return PendingSyncEntry(
      operation: SyncOperation.fromJson(Map<String, dynamic>.from(decoded)),
      state: PendingSyncState.values.byName(row['state'] as String),
      attemptCount: row['attempt_count'] as int,
      lastError: row['last_error'] as String?,
      updatedAtEpochMs: row['updated_at_ms'] as int,
    );
  }
}

final class MemoryPendingSyncQueueStore implements PendingSyncQueueStore {
  final Map<String, PendingSyncEntry> _entries = {};

  @override
  Future<List<PendingSyncEntry>> loadAll() async {
    final values = _entries.values.toList()
      ..sort((a, b) {
        final time = a.updatedAtEpochMs.compareTo(b.updatedAtEpochMs);
        if (time != 0) return time;
        return a.operation.operationId.compareTo(b.operation.operationId);
      });
    return List.unmodifiable(values);
  }

  @override
  Future<void> upsert(PendingSyncEntry entry) async {
    _entries[entry.operation.operationId] = entry;
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
