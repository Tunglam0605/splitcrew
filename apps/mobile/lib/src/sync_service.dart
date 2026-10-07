import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:splitcrew_domain/splitcrew_domain.dart';
import 'package:splitcrew_local_host/splitcrew_local_host.dart';
import 'package:splitcrew_sync_protocol/splitcrew_sync_protocol.dart';
import 'package:uuid/uuid.dart';

import 'app_state.dart';
import 'local_store.dart';
import 'sync_queue_store.dart';

enum MobileSyncMode { local, host, member }

enum SyncWriteDisposition { committed, queued }

final class MobileSyncController extends ChangeNotifier {
  MobileSyncController._({
    required this.tripController,
    http.Client? client,
    Uuid? uuid,
    TripRepository? snapshotRepository,
    PendingSyncQueueStore? queueStore,
    FlutterSecureStorage? secureStorage,
  })  : _client = client ?? http.Client(),
        _uuid = uuid ?? const Uuid(),
        _snapshotRepository = snapshotRepository ?? SqliteTripRepository(),
        _queueStore = queueStore ?? SqlitePendingSyncQueueStore(),
        _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const _sessionStorageKey = 'splitcrew.member-session.v2';

  final TripController tripController;
  final http.Client _client;
  final Uuid _uuid;
  final TripRepository _snapshotRepository;
  final PendingSyncQueueStore _queueStore;
  final FlutterSecureStorage _secureStorage;

  MobileSyncMode _mode = MobileSyncMode.local;
  LocalHostServer? _hostServer;
  String? _advertisedHost;

  Uri? _memberBaseUri;
  String? _memberSessionToken;
  String? _memberId;
  String? _pinnedHostId;
  int _canonicalRevision = 0;
  Timer? _pollTimer;
  Timer? _eventReconnectTimer;
  WebSocket? _memberEventSocket;
  bool _eventSocketConnecting = false;
  bool _eventRefreshInFlight = false;
  int _eventReconnectAttempt = 0;
  bool _memberOnline = false;
  bool _realtimeConnected = false;
  bool _busy = false;
  bool _flushingQueue = false;
  String? _lastError;
  DateTime? _lastSyncAt;
  List<PendingSyncEntry> _pending = const [];

  MobileSyncMode get mode => _mode;
  bool get isHostRunning => _hostServer?.isRunning ?? false;
  bool get isMemberSession => _mode == MobileSyncMode.member;
  bool get memberOnline => _memberOnline;
  bool get realtimeConnected => _realtimeConnected;
  bool get busy => _busy;
  bool get flushingQueue => _flushingQueue;
  String? get lastError => _lastError;
  DateTime? get lastSyncAt => _lastSyncAt;
  String? get memberId => _memberId;
  String? get pinnedHostId => _pinnedHostId;
  int get canonicalRevision => _canonicalRevision;
  String? get advertisedHost => _advertisedHost;
  int? get hostPort => _hostServer?.port;
  String? get hostId => _hostServer?.hostId;

  List<PendingSyncEntry> get pendingEntries {
    final tripId = tripController.trip?.id;
    if (tripId == null) return const [];
    return List.unmodifiable(_pending.where((entry) => entry.operation.tripId == tripId));
  }

  int get pendingCount => pendingEntries.where((entry) => entry.state == PendingSyncState.queued).length;
  int get blockedCount => pendingEntries.where((entry) => entry.state == PendingSyncState.blocked).length;

  static Future<MobileSyncController> bootstrap(TripController tripController) async {
    final controller = MobileSyncController._(tripController: tripController);
    await controller._reloadQueue();
    await controller._restoreMemberSession();
    return controller;
  }

  @visibleForTesting
  static Future<MobileSyncController> memberSessionForTesting({
    required TripController tripController,
    required String memberId,
    required int canonicalRevision,
    required PendingSyncQueueStore queueStore,
    Uri? baseUri,
    String? sessionToken,
    bool online = false,
    http.Client? client,
    Uuid? uuid,
    TripRepository? snapshotRepository,
  }) async {
    final controller = MobileSyncController._(
      tripController: tripController,
      client: client,
      uuid: uuid,
      snapshotRepository: snapshotRepository,
      queueStore: queueStore,
    );
    controller
      .._mode = MobileSyncMode.member
      .._memberId = memberId
      .._canonicalRevision = canonicalRevision
      .._memberBaseUri = baseUri
      .._memberSessionToken = sessionToken
      .._memberOnline = online;
    await controller._reloadQueue();
    return controller;
  }

  @visibleForTesting
  static HostTripBackend hostBackendForTesting(TripController tripController, {Uuid? uuid}) =>
      _MobileTripHostBackend(tripController, uuid: uuid);

  Future<void> startHost() async {
    if (_mode == MobileSyncMode.member) {
      throw StateError('Leave the member session before starting a host.');
    }
    if (!tripController.hasTrip) throw StateError('Create a crew before starting a host session.');
    if (isHostRunning) return;

    _setBusy(true);
    try {
      final host = await _discoverLanIpv4();
      final backend = _MobileTripHostBackend(tripController, uuid: _uuid);
      final server = LocalHostServer(backend: backend);
      await server.start(address: InternetAddress.anyIPv4);
      _hostServer = server;
      _advertisedHost = host;
      _mode = MobileSyncMode.host;
      _lastError = null;
      notifyListeners();
    } catch (error) {
      _lastError = 'Unable to start local host: $error';
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> stopHost() async {
    final server = _hostServer;
    _hostServer = null;
    _advertisedHost = null;
    if (server != null) await server.stop();
    if (_mode == MobileSyncMode.host) _mode = MobileSyncMode.local;
    notifyListeners();
  }

  String createInviteForMember(String memberId) {
    final server = _hostServer;
    final host = _advertisedHost;
    if (server == null || host == null || !server.isRunning) {
      throw StateError('Start the host session first.');
    }
    final trip = tripController.trip!;
    final member = trip.members.where((item) => item.id == memberId).firstOrNull;
    if (member == null) throw ArgumentError('Member not found.');
    if (member.isOwner) throw ArgumentError('Create invites for non-owner members only.');
    return server.createInvite(memberId: memberId, advertisedHost: host).encode();
  }

  Future<void> joinFromInvite(String encodedInvite) async {
    if (isHostRunning) throw StateError('Stop the host session before joining another host.');
    final invite = LocalHostInvite.decode(encodedInvite.trim());
    if (invite.isExpiredAt(DateTime.now().millisecondsSinceEpoch)) {
      throw StateError('This invite has expired. Ask the owner for a new invite.');
    }

    _setBusy(true);
    try {
      final health = await _getJson(invite.baseUri.resolve('/v1/health'));
      if (health['hostId'] != invite.hostId || health['tripId'] != invite.tripId) {
        throw StateError('The host identity does not match the invite.');
      }
      final response = await _client
          .post(
            invite.baseUri.resolve('/v1/join'),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode({'invite': invite.encode()}),
          )
          .timeout(const Duration(seconds: 8));
      final body = _decodeBody(response.body);
      if (response.statusCode != 200) {
        throw StateError('Join rejected: ${body['error'] ?? response.statusCode}');
      }

      final token = body['sessionToken'] as String?;
      final memberId = body['memberId'] as String?;
      final hostId = body['hostId'] as String?;
      if (token == null || memberId == null || hostId != invite.hostId) {
        throw const FormatException('Host returned an invalid join response.');
      }
      final snapshot = TripSnapshotEnvelope.fromJson(
        Map<String, dynamic>.from(body['snapshot'] as Map),
      );
      if (snapshot.tripId != invite.tripId) throw const FormatException('Snapshot trip mismatch.');

      await _replaceSnapshot(snapshot.snapshot);
      _memberBaseUri = invite.baseUri;
      _memberSessionToken = token;
      _memberId = memberId;
      _pinnedHostId = hostId;
      _canonicalRevision = snapshot.revision;
      _memberOnline = true;
      _mode = MobileSyncMode.member;
      _lastError = null;
      _lastSyncAt = DateTime.now();
      await _persistMemberSession();
      await _reloadQueue();
      _startPolling();
      unawaited(_connectEventSocket());
      notifyListeners();
      unawaited(flushPendingQueue());
    } catch (error) {
      _lastError = 'Unable to join crew: $error';
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> leaveMemberSession({
    bool keepCachedTrip = true,
    bool clearPendingOperations = false,
  }) async {
    final tripId = tripController.trip?.id;
    _pollTimer?.cancel();
    _pollTimer = null;
    _mode = MobileSyncMode.local;
    await _disconnectEventSocket();
    _memberBaseUri = null;
    _memberSessionToken = null;
    _memberId = null;
    _pinnedHostId = null;
    _canonicalRevision = 0;
    _memberOnline = false;
    _lastSyncAt = null;
    _lastError = null;
    await _secureStorage.delete(key: _sessionStorageKey);
    if (clearPendingOperations && tripId != null) {
      await _queueStore.clearForTrip(tripId);
      await _reloadQueue();
    }
    if (!keepCachedTrip) await tripController.reset();
    notifyListeners();
  }

  Future<void> refreshMemberSnapshot() async {
    if (_mode != MobileSyncMode.member) return;
    final uri = _memberBaseUri;
    final token = _memberSessionToken;
    if (uri == null || token == null) throw StateError('No active host session token.');
    try {
      final response = await _client
          .get(
            uri.resolve('/v1/snapshot'),
            headers: {'authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 6));
      if (response.statusCode == 401) {
        throw StateError('Host session expired. Ask the owner for a new invite.');
      }
      if (response.statusCode != 200) throw StateError('Snapshot request failed (${response.statusCode}).');
      final snapshot = TripSnapshotEnvelope.fromJson(_decodeBody(response.body));
      if (snapshot.tripId != tripController.trip?.id) throw StateError('Snapshot belongs to another trip.');
      await _replaceSnapshot(snapshot.snapshot);
      _canonicalRevision = snapshot.revision;
      _memberOnline = true;
      _lastError = null;
      _lastSyncAt = DateTime.now();
      await _persistMemberSession();
      notifyListeners();
    } catch (error) {
      _memberOnline = false;
      _lastError = '$error';
      notifyListeners();
      rethrow;
    }
  }

  Future<SyncWriteDisposition> createExpense({
    required String title,
    required int totalMinor,
    required List<ExpensePayer> payers,
    required List<ExpenseAllocation> allocations,
  }) async {
    if (_mode != MobileSyncMode.member) {
      await tripController.addExpense(
        title: title,
        totalMinor: totalMinor,
        payers: payers,
        allocations: allocations,
      );
      return SyncWriteDisposition.committed;
    }
    return _enqueueMemberOperation(
      SyncOperationType.createExpense,
      {
        'title': title,
        'totalMinor': totalMinor,
        'payers': {for (final payer in payers) payer.memberId: payer.amount.minorUnits},
        'allocations': {for (final allocation in allocations) allocation.memberId: allocation.amount.minorUnits},
      },
    );
  }

  Future<SyncWriteDisposition> updateExpense({
    required String expenseId,
    required String title,
    required int totalMinor,
    required List<ExpensePayer> payers,
    required List<ExpenseAllocation> allocations,
  }) async {
    if (_mode != MobileSyncMode.member) {
      await tripController.updateExpense(
        expenseId: expenseId,
        title: title,
        totalMinor: totalMinor,
        payers: payers,
        allocations: allocations,
      );
      return SyncWriteDisposition.committed;
    }

    final expense = tripController.expenseById(expenseId);
    final actor = _memberId;
    if (expense == null) throw ArgumentError('Expense not found.');
    if (actor == null) throw StateError('No active member profile.');
    if (expense.createdByMemberId != actor) {
      throw StateError('Members may only edit expenses they created.');
    }

    return _enqueueMemberOperation(
      SyncOperationType.updateExpense,
      {
        'expenseId': expenseId,
        'expectedExpenseVersion': expense.version,
        'title': title,
        'totalMinor': totalMinor,
        'payers': {for (final payer in payers) payer.memberId: payer.amount.minorUnits},
        'allocations': {for (final allocation in allocations) allocation.memberId: allocation.amount.minorUnits},
      },
    );
  }

  Future<SyncWriteDisposition> deleteExpense(String expenseId) async {
    if (_mode != MobileSyncMode.member) {
      await tripController.removeExpense(expenseId);
      return SyncWriteDisposition.committed;
    }

    final expense = tripController.expenseById(expenseId);
    final actor = _memberId;
    if (expense == null) throw ArgumentError('Expense not found.');
    if (actor == null) throw StateError('No active member profile.');
    if (expense.createdByMemberId != actor) {
      throw StateError('Members may only delete expenses they created.');
    }

    return _enqueueMemberOperation(
      SyncOperationType.deleteExpense,
      {
        'expenseId': expenseId,
        'expectedExpenseVersion': expense.version,
      },
    );
  }

  Future<SyncWriteDisposition> renameMember({
    required String memberId,
    required String name,
  }) async {
    if (_mode != MobileSyncMode.member) {
      await tripController.renameMember(memberId, name);
      return SyncWriteDisposition.committed;
    }

    final trip = tripController.trip;
    final actor = _memberId;
    if (trip == null || actor == null) throw StateError('No active member profile.');
    if (memberId != actor) throw StateError('Members may only rename their own profile.');
    final member = trip.members.where((item) => item.id == memberId).firstOrNull;
    if (member == null) throw ArgumentError('Member not found.');

    return _enqueueMemberOperation(
      SyncOperationType.renameMember,
      {
        'memberId': memberId,
        'expectedMemberVersion': member.version,
        'name': name,
      },
    );
  }

  Future<SyncWriteDisposition> updatePaymentAccount({
    required String memberId,
    required String holderName,
    required String bankBin,
    required String accountIdentifier,
  }) async {
    if (_mode != MobileSyncMode.member) {
      await tripController.upsertPaymentAccount(
        memberId: memberId,
        holderName: holderName,
        bankBin: bankBin,
        accountIdentifier: accountIdentifier,
      );
      return SyncWriteDisposition.committed;
    }

    final trip = tripController.trip;
    final actor = _memberId;
    if (trip == null || actor == null) throw StateError('No active member profile.');
    if (memberId != actor) throw StateError('Members may only update their own payment profile.');
    if (!trip.members.any((member) => member.id == memberId)) {
      throw ArgumentError('Member not found.');
    }
    final existing = trip.paymentAccounts.where((account) => account.memberId == memberId).firstOrNull;

    return _enqueueMemberOperation(
      SyncOperationType.updatePaymentAccount,
      {
        'memberId': memberId,
        'expectedPaymentAccountVersion': existing?.version,
        'holderName': holderName,
        'bankBin': bankBin,
        'accountIdentifier': accountIdentifier,
      },
    );
  }

  Future<SyncWriteDisposition> markSettlement({
    required String fromMemberId,
    required String toMemberId,
    required int amountMinor,
  }) async {
    final trip = tripController.trip;
    if (trip == null) throw StateError('No active trip.');

    if (_mode != MobileSyncMode.member) {
      final owner = trip.members.where((member) => member.isOwner).firstOrNull;
      if (owner == null) throw StateError('Trip owner is missing.');
      await tripController.acknowledgeSettlement(
        fromMemberId: fromMemberId,
        toMemberId: toMemberId,
        amountMinor: amountMinor,
        confirmedByMemberId: owner.id,
      );
      return SyncWriteDisposition.committed;
    }

    final actor = _memberId;
    if (actor == null) throw StateError('No active member profile.');
    if (fromMemberId != actor) {
      throw StateError('Members may only record their own outgoing settlement.');
    }
    final stillSuggested = tripController.settlements.any(
      (transfer) =>
          transfer.fromMemberId == fromMemberId &&
          transfer.toMemberId == toMemberId &&
          transfer.amount.minorUnits == amountMinor,
    );
    if (!stillSuggested) {
      throw StateError('This settlement suggestion is no longer current. Refresh before recording payment.');
    }

    return _enqueueMemberOperation(
      SyncOperationType.markSettlement,
      {
        'fromMemberId': fromMemberId,
        'toMemberId': toMemberId,
        'amountMinor': amountMinor,
      },
    );
  }

  Future<SyncWriteDisposition> _enqueueMemberOperation(
    SyncOperationType type,
    Map<String, Object?> payload,
  ) async {
    final trip = tripController.trip;
    final actor = _memberId;
    if (trip == null || actor == null) throw StateError('No active member profile.');

    final operation = SyncOperation(
      operationId: _uuid.v4(),
      tripId: trip.id,
      actorMemberId: actor,
      expectedTripRevision: _canonicalRevision,
      type: type,
      payload: payload,
      createdAtEpochMs: DateTime.now().millisecondsSinceEpoch,
    );
    final entry = PendingSyncEntry(
      operation: operation,
      state: PendingSyncState.queued,
      attemptCount: 0,
      updatedAtEpochMs: DateTime.now().millisecondsSinceEpoch,
    );
    await _queueStore.upsert(entry);
    await _reloadQueue();

    if (!_memberOnline || _memberSessionToken == null || _memberBaseUri == null) {
      _lastError = 'Operation queued. It will be sent when the owner host is reachable again.';
      notifyListeners();
      return SyncWriteDisposition.queued;
    }
    return _deliverQueuedEntry(entry);
  }
  Future<void> flushPendingQueue() async {
    if (_flushingQueue || _mode != MobileSyncMode.member) return;
    if (_memberBaseUri == null || _memberSessionToken == null || _memberId == null) return;
    _flushingQueue = true;
    notifyListeners();
    try {
      await _reloadQueue();
      final tripId = tripController.trip?.id;
      final actor = _memberId;
      if (tripId == null || actor == null) return;
      final queue = _pending
          .where(
            (entry) =>
                entry.state == PendingSyncState.queued &&
                entry.operation.tripId == tripId &&
                entry.operation.actorMemberId == actor,
          )
          .toList();
      for (final entry in queue) {
        final disposition = await _deliverQueuedEntry(entry);
        if (disposition == SyncWriteDisposition.queued && !_memberOnline) break;
      }
    } finally {
      _flushingQueue = false;
      notifyListeners();
    }
  }

  Future<void> discardPendingOperation(String operationId) async {
    await _queueStore.delete(operationId);
    await _reloadQueue();
    notifyListeners();
  }

  Future<void> clearPendingOperationsForTrip(String tripId) async {
    if (tripId.trim().isEmpty) return;
    await _queueStore.clearForTrip(tripId);
    await _reloadQueue();
    notifyListeners();
  }

  Future<SyncWriteDisposition> _deliverQueuedEntry(PendingSyncEntry original) async {
    final baseUri = _memberBaseUri;
    final token = _memberSessionToken;
    if (baseUri == null || token == null) return SyncWriteDisposition.queued;

    final existing = _pending.where((entry) => entry.operation.operationId == original.operation.operationId).firstOrNull;
    final entry = (existing ?? original).copyWith(
      attemptCount: (existing ?? original).attemptCount + 1,
      updatedAtEpochMs: DateTime.now().millisecondsSinceEpoch,
      clearLastError: true,
      state: PendingSyncState.queued,
    );
    await _queueStore.upsert(entry);
    await _reloadQueue();

    try {
      final response = await _client
          .post(
            baseUri.resolve('/v1/operations'),
            headers: {
              'authorization': 'Bearer $token',
              'content-type': 'application/json',
            },
            body: jsonEncode(entry.operation.toJson()),
          )
          .timeout(const Duration(seconds: 8));
      final body = _decodeBody(response.body);

      if (response.statusCode == 401) {
        await _keepQueued(entry, 'Host session expired. Rejoin using a new owner invite.');
        _memberOnline = false;
        return SyncWriteDisposition.queued;
      }
      if (response.statusCode == 403 || response.statusCode == 400) {
        final message = body['message']?.toString() ?? body['error']?.toString() ?? 'Operation not permitted.';
        await _blockEntry(entry, message);
        throw StateError(message);
      }
      if (response.statusCode >= 500) {
        await _keepQueued(entry, 'Owner host returned ${response.statusCode}. Retrying later.');
        _memberOnline = false;
        return SyncWriteDisposition.queued;
      }

      final result = SyncOperationResult.fromJson(body);
      if (result.status == SyncResultStatus.conflict) {
        _canonicalRevision = result.canonicalTripRevision;

        if (result.errorCode != 'STALE_REVISION') {
          try {
            await refreshMemberSnapshot();
          } catch (_) {
            // Keep the explicit entity conflict even if the refresh must wait for the next poll.
          }
          final message = result.message ?? result.errorCode ?? 'The owner rejected a stale entity version.';
          await _blockEntry(entry, message);
          return SyncWriteDisposition.queued;
        }

        final targetsExistingExpense = entry.operation.type == SyncOperationType.updateExpense ||
            entry.operation.type == SyncOperationType.deleteExpense;
        if (targetsExistingExpense) {
          try {
            await refreshMemberSnapshot();
          } catch (_) {
            await _keepQueued(
              entry,
              'Owner state changed. Waiting for a canonical refresh before retrying this edit/delete.',
            );
            return SyncWriteDisposition.queued;
          }

          final expenseId = entry.operation.payload['expenseId'] as String?;
          final expectedVersion = entry.operation.payload['expectedExpenseVersion'] as int?;
          final currentExpense = expenseId == null ? null : tripController.expenseById(expenseId);
          if (currentExpense == null) {
            await _blockEntry(entry, 'This expense no longer exists on the owner device.');
            return SyncWriteDisposition.queued;
          }
          if (expectedVersion == null || currentExpense.version != expectedVersion) {
            await _blockEntry(
              entry,
              'This expense changed on the owner device. Review the latest version before retrying.',
            );
            return SyncWriteDisposition.queued;
          }
        } else {
          try {
            await refreshMemberSnapshot();
          } catch (_) {
            // Create operations remain safe to rebase because the host revalidates the complete payload.
          }
        }

        final rebased = PendingSyncEntry(
          operation: SyncOperation(
            operationId: _uuid.v4(),
            tripId: entry.operation.tripId,
            actorMemberId: entry.operation.actorMemberId,
            expectedTripRevision: result.canonicalTripRevision,
            type: entry.operation.type,
            payload: entry.operation.payload,
            createdAtEpochMs: DateTime.now().millisecondsSinceEpoch,
          ),
          state: PendingSyncState.queued,
          attemptCount: 0,
          updatedAtEpochMs: DateTime.now().millisecondsSinceEpoch,
          enqueueSequence: entry.enqueueSequence,
          lastError: 'Rebased after stale revision ${entry.operation.expectedTripRevision}.',
        );
        await _queueStore.upsert(rebased);
        await _queueStore.delete(entry.operation.operationId);
        await _reloadQueue();
        return SyncWriteDisposition.queued;
      }
      if (result.status == SyncResultStatus.rejected) {
        final message = result.message ?? result.errorCode ?? 'Host rejected the operation.';
        await _blockEntry(entry, message);
        throw StateError(message);
      }

      await _queueStore.delete(entry.operation.operationId);
      _canonicalRevision = result.canonicalTripRevision;
      _memberOnline = true;
      _lastError = null;
      _lastSyncAt = DateTime.now();
      await _reloadQueue();
      try {
        await refreshMemberSnapshot();
      } catch (_) {
        // Commit is already authoritative. The next poll will refresh the local cache.
      }
      notifyListeners();
      return SyncWriteDisposition.committed;
    } on TimeoutException {
      await _keepQueued(entry, 'Owner host did not respond. Retrying when the LAN session returns.');
      _memberOnline = false;
      return SyncWriteDisposition.queued;
    } on SocketException catch (error) {
      await _keepQueued(entry, 'Owner host is unreachable: $error');
      _memberOnline = false;
      return SyncWriteDisposition.queued;
    } on FormatException catch (error) {
      await _blockEntry(entry, 'Invalid host response: $error');
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  Future<void> _keepQueued(PendingSyncEntry entry, String error) async {
    _lastError = error;
    await _queueStore.upsert(
      entry.copyWith(
        state: PendingSyncState.queued,
        lastError: error,
        updatedAtEpochMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    await _reloadQueue();
  }

  Future<void> _blockEntry(PendingSyncEntry entry, String error) async {
    _lastError = error;
    await _queueStore.upsert(
      entry.copyWith(
        state: PendingSyncState.blocked,
        lastError: error,
        updatedAtEpochMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    await _reloadQueue();
  }

  Future<void> _connectEventSocket() async {
    if (_mode != MobileSyncMode.member || _eventSocketConnecting || _memberEventSocket != null) return;
    final baseUri = _memberBaseUri;
    final token = _memberSessionToken;
    if (baseUri == null || token == null) return;

    _eventSocketConnecting = true;
    try {
      final eventUri = baseUri.resolve('/v1/events/ws');
      final socketUri = eventUri.replace(scheme: eventUri.scheme == 'https' ? 'wss' : 'ws');
      final socket = await WebSocket.connect(
        socketUri.toString(),
        headers: {HttpHeaders.authorizationHeader: 'Bearer $token'},
      ).timeout(const Duration(seconds: 6));

      if (_mode != MobileSyncMode.member || token != _memberSessionToken) {
        await socket.close();
        return;
      }

      _memberEventSocket = socket;
      _eventReconnectAttempt = 0;
      _realtimeConnected = true;
      notifyListeners();
      if (pendingCount > 0) unawaited(flushPendingQueue());
      socket.listen(
        _handleEventSocketMessage,
        onDone: () => _handleEventSocketClosed(socket),
        onError: (_) => _handleEventSocketClosed(socket),
        cancelOnError: true,
      );
    } on Object {
      _realtimeConnected = false;
      _scheduleEventSocketReconnect();
      notifyListeners();
    } finally {
      _eventSocketConnecting = false;
    }
  }

  Future<void> _disconnectEventSocket() async {
    _eventReconnectTimer?.cancel();
    _eventReconnectTimer = null;
    _eventReconnectAttempt = 0;
    final socket = _memberEventSocket;
    _memberEventSocket = null;
    _realtimeConnected = false;
    if (socket != null) await socket.close();
  }

  void _handleEventSocketClosed(WebSocket socket) {
    if (!identical(_memberEventSocket, socket)) return;
    _memberEventSocket = null;
    _realtimeConnected = false;
    notifyListeners();
    _scheduleEventSocketReconnect();
  }

  void _scheduleEventSocketReconnect() {
    if (_mode != MobileSyncMode.member || _eventReconnectTimer?.isActive == true) return;
    final delaySeconds = switch (_eventReconnectAttempt) {
      0 => 2,
      1 => 4,
      2 => 8,
      3 => 15,
      _ => 30,
    };
    _eventReconnectAttempt++;
    _eventReconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      _eventReconnectTimer = null;
      unawaited(_connectEventSocket());
    });
  }

  void _handleEventSocketMessage(dynamic raw) {
    if (raw is! String) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final message = Map<String, dynamic>.from(decoded);
      final revision = message['canonicalTripRevision'] as int?;
      if (revision != null && revision > _canonicalRevision) {
        unawaited(_refreshFromRealtime());
      }
    } on FormatException {
      // Ignore malformed realtime notifications; REST polling remains authoritative.
    }
  }

  Future<void> _refreshFromRealtime() async {
    if (_eventRefreshInFlight || _mode != MobileSyncMode.member || _busy || _flushingQueue) return;
    _eventRefreshInFlight = true;
    try {
      await refreshMemberSnapshot();
      if (pendingCount > 0) await flushPendingQueue();
    } catch (_) {
      // Socket notifications are hints only; the REST fallback retries canonical refresh.
    } finally {
      _eventRefreshInFlight = false;
    }
  }
  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      unawaited(_pollEvents());
    });
  }

  Future<void> _pollEvents() async {
    if (_mode != MobileSyncMode.member || _busy || _flushingQueue) return;
    final baseUri = _memberBaseUri;
    final token = _memberSessionToken;
    if (baseUri == null || token == null) return;
    try {
      final uri = baseUri.resolve('/v1/events?afterRevision=$_canonicalRevision');
      final response = await _client
          .get(uri, headers: {'authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 401) {
        _memberOnline = false;
        _lastError = 'Host session expired. Rejoin using a new owner invite.';
        notifyListeners();
        return;
      }
      if (response.statusCode != 200) throw StateError('Event polling failed (${response.statusCode}).');
      final body = _decodeBody(response.body);
      final revision = body['canonicalTripRevision'] as int? ?? _canonicalRevision;
      if (revision > _canonicalRevision) {
        await refreshMemberSnapshot();
      } else {
        _memberOnline = true;
        _lastError = null;
        _lastSyncAt = DateTime.now();
        notifyListeners();
      }
      if (pendingCount > 0) unawaited(flushPendingQueue());
    } catch (error) {
      _memberOnline = false;
      _lastError = '$error';
      notifyListeners();
    }
  }

  Future<void> _restoreMemberSession() async {
    final raw = await _secureStorage.read(key: _sessionStorageKey);
    if (raw == null || !tripController.hasTrip) return;
    try {
      final json = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      _memberBaseUri = Uri.parse(json['baseUri'] as String);
      _memberSessionToken = json['sessionToken'] as String;
      _memberId = json['memberId'] as String;
      _pinnedHostId = json['hostId'] as String;
      _canonicalRevision = json['revision'] as int? ?? tripController.trip!.version;
      _mode = MobileSyncMode.member;
      _startPolling();
      unawaited(_connectEventSocket());
      try {
        await refreshMemberSnapshot();
        unawaited(flushPendingQueue());
      } catch (_) {
        _memberOnline = false;
        // Keep member mode so cached canonical data and pending intents cannot be mistaken for owner-local state.
      }
    } catch (error) {
      _memberOnline = false;
      _mode = MobileSyncMode.local;
      _lastError = 'Saved host session could not be restored: $error';
    }
  }

  Future<void> _persistMemberSession() async {
    final baseUri = _memberBaseUri;
    final token = _memberSessionToken;
    final memberId = _memberId;
    final hostId = _pinnedHostId;
    if (baseUri == null || token == null || memberId == null || hostId == null) return;
    await _secureStorage.write(
      key: _sessionStorageKey,
      value: jsonEncode({
        'baseUri': baseUri.toString(),
        'sessionToken': token,
        'memberId': memberId,
        'hostId': hostId,
        'revision': _canonicalRevision,
      }),
    );
  }

  Future<void> _reloadQueue() async {
    _pending = await _queueStore.loadAll();
    notifyListeners();
  }

  Future<void> _replaceSnapshot(Map<String, Object?> snapshot) async {
    final stored = StoredTrip.fromJson(Map<String, dynamic>.from(snapshot));
    await _snapshotRepository.save(stored);
    await tripController.load();
  }

  Future<String> _discoverLanIpv4() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: false,
    );
    final candidates = <String>[];
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (_isPrivateIpv4(address.address)) candidates.add(address.address);
      }
    }
    if (candidates.isEmpty) {
      throw StateError('No private IPv4 address found. Connect both phones to the same Wi-Fi or hotspot.');
    }
    return candidates.first;
  }

  bool _isPrivateIpv4(String value) {
    final parsed = value.split('.').map(int.tryParse).toList();
    if (parsed.length != 4 || parsed.any((part) => part == null)) return false;
    final a = parsed[0]!;
    final b = parsed[1]!;
    return a == 10 || (a == 172 && b >= 16 && b <= 31) || (a == 192 && b == 168);
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final response = await _client.get(uri).timeout(const Duration(seconds: 6));
    if (response.statusCode != 200) throw StateError('Host probe failed (${response.statusCode}).');
    return _decodeBody(response.body);
  }

  Map<String, dynamic> _decodeBody(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) throw const FormatException('JSON object required.');
    return Map<String, dynamic>.from(decoded);
  }

  void _setBusy(bool value) {
    _busy = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _eventReconnectTimer?.cancel();
    unawaited(_disconnectEventSocket());
    unawaited(_hostServer?.stop() ?? Future<void>.value());
    _client.close();
    super.dispose();
  }
}

final class _MobileTripHostBackend implements HostTripBackend {
  _MobileTripHostBackend(this.controller, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final TripController controller;
  final Uuid _uuid;
  final Map<String, SyncOperationResult> _processed = {};

  @override
  String get tripId => controller.trip!.id;

  @override
  int get revision => controller.trip!.version;

  @override
  bool canSubmit({required String memberId, required SyncOperationType type}) {
    final member = controller.trip?.members.where((item) => item.id == memberId).firstOrNull;
    if (member == null) return false;
    if (member.isOwner) return true;
    return type == SyncOperationType.createExpense ||
        type == SyncOperationType.updateExpense ||
        type == SyncOperationType.deleteExpense ||
        type == SyncOperationType.renameMember ||
        type == SyncOperationType.updatePaymentAccount ||
        type == SyncOperationType.markSettlement;
  }

  @override
  Future<TripSnapshotEnvelope> snapshot() async => TripSnapshotEnvelope(
        tripId: tripId,
        revision: revision,
        snapshot: _networkSnapshot(controller.trip!),
      );

  @override
  Future<SyncOperationResult> apply(SyncOperation operation) async {
    final prior = _processed[operation.operationId];
    if (prior != null) {
      return SyncOperationResult(
        operationId: prior.operationId,
        status: SyncResultStatus.duplicate,
        canonicalTripRevision: prior.canonicalTripRevision,
        event: prior.event,
        errorCode: prior.errorCode,
        message: 'Operation already processed.',
      );
    }
    if (operation.tripId != tripId) {
      return _remember(
        operation.operationId,
        SyncOperationResult(
          operationId: operation.operationId,
          status: SyncResultStatus.rejected,
          canonicalTripRevision: revision,
          errorCode: 'TRIP_MISMATCH',
        ),
      );
    }
    if (operation.expectedTripRevision != revision) {
      return _remember(
        operation.operationId,
        SyncOperationResult(
          operationId: operation.operationId,
          status: SyncResultStatus.conflict,
          canonicalTripRevision: revision,
          errorCode: 'STALE_REVISION',
          message: 'The host has newer data. Refresh and retry.',
        ),
      );
    }

    try {
      await _applyAuthorized(operation);
      final event = CommittedSyncEvent(
        eventId: _uuid.v4(),
        tripId: tripId,
        revision: revision,
        operationId: operation.operationId,
        type: operation.type,
        payload: operation.payload,
        committedAtEpochMs: DateTime.now().millisecondsSinceEpoch,
      );
      return _remember(
        operation.operationId,
        SyncOperationResult(
          operationId: operation.operationId,
          status: SyncResultStatus.accepted,
          canonicalTripRevision: revision,
          event: event,
        ),
      );
    } on _EntityVersionConflict catch (error) {
      return _remember(
        operation.operationId,
        SyncOperationResult(
          operationId: operation.operationId,
          status: SyncResultStatus.conflict,
          canonicalTripRevision: revision,
          errorCode: 'ENTITY_VERSION_CONFLICT',
          message: error.message,
        ),
      );
    } on _ForbiddenOperation catch (error) {
      return _remember(
        operation.operationId,
        SyncOperationResult(
          operationId: operation.operationId,
          status: SyncResultStatus.rejected,
          canonicalTripRevision: revision,
          errorCode: 'OPERATION_FORBIDDEN',
          message: error.message,
        ),
      );
    } on Object catch (error) {
      return _remember(
        operation.operationId,
        SyncOperationResult(
          operationId: operation.operationId,
          status: SyncResultStatus.rejected,
          canonicalTripRevision: revision,
          errorCode: 'OPERATION_INVALID',
          message: '$error',
        ),
      );
    }
  }

  Future<void> _applyAuthorized(SyncOperation operation) async {
    final trip = controller.trip!;
    final actor = trip.members.where((item) => item.id == operation.actorMemberId).firstOrNull;
    if (actor == null) throw const _ForbiddenOperation('Unknown member.');
    final isOwner = actor.isOwner;
    final payload = operation.payload;

    switch (operation.type) {
      case SyncOperationType.createExpense:
        await controller.addExpense(
          title: payload['title'] as String,
          totalMinor: payload['totalMinor'] as int,
          payers: _payers(payload['payers'], trip.currencyCode),
          allocations: _allocations(payload['allocations'], trip.currencyCode),
          createdByMemberId: actor.id,
        );
      case SyncOperationType.updateExpense:
        final expenseId = payload['expenseId'] as String;
        final expense = controller.expenseById(expenseId);
        if (expense == null) throw ArgumentError('Expense not found.');
        if (!isOwner && expense.createdByMemberId != actor.id) {
          throw const _ForbiddenOperation('Members may only edit expenses they created.');
        }
        final expectedVersion = payload['expectedExpenseVersion'] as int?;
        if (expectedVersion == null || expectedVersion != expense.version) {
          throw _EntityVersionConflict(
            'Expense version changed from ${expectedVersion ?? 'unknown'} to ${expense.version}.',
          );
        }
        await controller.updateExpense(
          expenseId: expenseId,
          title: payload['title'] as String,
          totalMinor: payload['totalMinor'] as int,
          payers: _payers(payload['payers'], trip.currencyCode),
          allocations: _allocations(payload['allocations'], trip.currencyCode),
        );
      case SyncOperationType.deleteExpense:
        final expenseId = payload['expenseId'] as String;
        final expense = controller.expenseById(expenseId);
        if (expense == null) throw ArgumentError('Expense not found.');
        if (!isOwner && expense.createdByMemberId != actor.id) {
          throw const _ForbiddenOperation('Members may only delete expenses they created.');
        }
        final expectedVersion = payload['expectedExpenseVersion'] as int?;
        if (expectedVersion == null || expectedVersion != expense.version) {
          throw _EntityVersionConflict(
            'Expense version changed from ${expectedVersion ?? 'unknown'} to ${expense.version}.',
          );
        }
        await controller.removeExpense(expenseId);
      case SyncOperationType.addMember:
        if (!isOwner) throw const _ForbiddenOperation('Only the owner can add members.');
        await controller.addMember(payload['name'] as String);
      case SyncOperationType.renameMember:
        final targetId = payload['memberId'] as String;
        if (!isOwner && targetId != actor.id) {
          throw const _ForbiddenOperation('Members may only rename their own profile.');
        }
        final target = trip.members.where((member) => member.id == targetId).firstOrNull;
        if (target == null) throw ArgumentError('Member not found.');
        final expectedMemberVersion = payload['expectedMemberVersion'] as int?;
        if (expectedMemberVersion == null || expectedMemberVersion != target.version) {
          throw _EntityVersionConflict(
            'Member version changed from ${expectedMemberVersion ?? 'unknown'} to ${target.version}.',
          );
        }
        await controller.renameMember(targetId, payload['name'] as String);
      case SyncOperationType.updatePaymentAccount:
        final targetId = payload['memberId'] as String;
        if (!isOwner && targetId != actor.id) {
          throw const _ForbiddenOperation('Members may only update their own payment profile.');
        }
        if (!payload.containsKey('expectedPaymentAccountVersion')) {
          throw const _EntityVersionConflict('Payment account version is required.');
        }
        final existing = trip.paymentAccounts.where((account) => account.memberId == targetId).firstOrNull;
        final expectedPaymentVersion = payload['expectedPaymentAccountVersion'] as int?;
        final actualPaymentVersion = existing?.version;
        if (expectedPaymentVersion != actualPaymentVersion) {
          throw _EntityVersionConflict(
            'Payment account version changed from ${expectedPaymentVersion ?? 'none'} to ${actualPaymentVersion ?? 'none'}.',
          );
        }
        await controller.upsertPaymentAccount(
          memberId: targetId,
          holderName: payload['holderName'] as String,
          bankBin: payload['bankBin'] as String,
          accountIdentifier: payload['accountIdentifier'] as String,
        );
      case SyncOperationType.markSettlement:
        final fromMemberId = payload['fromMemberId'] as String;
        final toMemberId = payload['toMemberId'] as String;
        final amountMinor = payload['amountMinor'] as int;
        if (!isOwner && fromMemberId != actor.id) {
          throw const _ForbiddenOperation('Members may only record their own outgoing settlement.');
        }
        final stillSuggested = controller.settlements.any(
          (transfer) =>
              transfer.fromMemberId == fromMemberId &&
              transfer.toMemberId == toMemberId &&
              transfer.amount.minorUnits == amountMinor,
        );
        if (!stillSuggested) {
          throw const _EntityVersionConflict(
            'Settlement suggestion changed on the owner device. Refresh before recording payment.',
          );
        }
        await controller.acknowledgeSettlement(
          fromMemberId: fromMemberId,
          toMemberId: toMemberId,
          amountMinor: amountMinor,
          confirmedByMemberId: actor.id,
        );
    }
  }

  SyncOperationResult _remember(String operationId, SyncOperationResult result) {
    _processed[operationId] = result;
    if (_processed.length > 1000) _processed.remove(_processed.keys.first);
    return result;
  }

  Map<String, Object?> _networkSnapshot(StoredTrip trip) {
    final json = trip.toJson();
    final expenses = (json['expenses'] as List<Object?>).map((raw) {
      final expense = Map<String, Object?>.from(raw as Map);
      // Receipt files remain host-local until media synchronization is implemented.
      expense['receipts'] = <Object?>[];
      return expense;
    }).toList();
    return {...json, 'expenses': expenses};
  }

  List<ExpensePayer> _payers(Object? raw, String currency) {
    final values = _intMap(raw);
    return [
      for (final entry in values.entries)
        ExpensePayer(
          memberId: entry.key,
          amount: Money(minorUnits: entry.value, currencyCode: currency),
        ),
    ];
  }

  List<ExpenseAllocation> _allocations(Object? raw, String currency) {
    final values = _intMap(raw);
    return [
      for (final entry in values.entries)
        ExpenseAllocation(
          memberId: entry.key,
          amount: Money(minorUnits: entry.value, currencyCode: currency),
        ),
    ];
  }

  Map<String, int> _intMap(Object? raw) {
    if (raw is! Map) throw const FormatException('Expected an amount map.');
    return Map<String, dynamic>.from(raw).map((key, value) => MapEntry(key, value as int));
  }
}

final class _EntityVersionConflict implements Exception {
  const _EntityVersionConflict(this.message);
  final String message;
}

final class _ForbiddenOperation implements Exception {
  const _ForbiddenOperation(this.message);
  final String message;
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
