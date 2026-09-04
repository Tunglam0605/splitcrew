import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:splitcrew_domain/splitcrew_domain.dart';
import 'package:splitcrew_local_host/splitcrew_local_host.dart';
import 'package:splitcrew_sync_protocol/splitcrew_sync_protocol.dart';
import 'package:uuid/uuid.dart';

import 'app_state.dart';

enum MobileSyncMode { local, host, member }

final class MobileSyncController extends ChangeNotifier {
  MobileSyncController._({
    required this.tripController,
    http.Client? client,
    Uuid? uuid,
  })  : _client = client ?? http.Client(),
        _uuid = uuid ?? const Uuid();

  static const _prefsKey = 'splitcrew.member-session.v1';

  final TripController tripController;
  final http.Client _client;
  final Uuid _uuid;

  MobileSyncMode _mode = MobileSyncMode.local;
  LocalHostServer? _hostServer;
  String? _advertisedHost;

  Uri? _memberBaseUri;
  String? _memberSessionToken;
  String? _memberId;
  String? _pinnedHostId;
  int _canonicalRevision = 0;
  Timer? _pollTimer;
  bool _memberOnline = false;
  bool _busy = false;
  String? _lastError;
  DateTime? _lastSyncAt;

  MobileSyncMode get mode => _mode;
  bool get isHostRunning => _hostServer?.isRunning ?? false;
  bool get isMemberSession => _mode == MobileSyncMode.member;
  bool get memberOnline => _memberOnline;
  bool get busy => _busy;
  String? get lastError => _lastError;
  DateTime? get lastSyncAt => _lastSyncAt;
  String? get memberId => _memberId;
  String? get pinnedHostId => _pinnedHostId;
  int get canonicalRevision => _canonicalRevision;
  String? get advertisedHost => _advertisedHost;
  int? get hostPort => _hostServer?.port;
  String? get hostId => _hostServer?.hostId;

  static Future<MobileSyncController> bootstrap(TripController tripController) async {
    final controller = MobileSyncController._(tripController: tripController);
    await controller._restoreMemberSession();
    return controller;
  }

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
      final response = await _client.post(
        invite.baseUri.resolve('/v1/join'),
        headers: const {'content-type': 'application/json'},
        body: jsonEncode({'invite': invite.encode()}),
      ).timeout(const Duration(seconds: 8));
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

      await tripController.replaceFromSyncSnapshot(snapshot.snapshot);
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
      _startPolling();
      notifyListeners();
    } catch (error) {
      _lastError = 'Unable to join crew: $error';
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> leaveMemberSession({bool keepCachedTrip = true}) async {
    _pollTimer?.cancel();
    _pollTimer = null;
    _memberBaseUri = null;
    _memberSessionToken = null;
    _memberId = null;
    _pinnedHostId = null;
    _canonicalRevision = 0;
    _memberOnline = false;
    _lastSyncAt = null;
    _lastError = null;
    _mode = MobileSyncMode.local;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    if (!keepCachedTrip) await tripController.reset();
    notifyListeners();
  }

  Future<void> refreshMemberSnapshot() async {
    if (_mode != MobileSyncMode.member) return;
    final uri = _memberBaseUri;
    final token = _memberSessionToken;
    if (uri == null || token == null) return;
    try {
      final response = await _client.get(
        uri.resolve('/v1/snapshot'),
        headers: {'authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 6));
      if (response.statusCode == 401) {
        throw StateError('Host session expired. Ask the owner for a new invite.');
      }
      if (response.statusCode != 200) throw StateError('Snapshot request failed (${response.statusCode}).');
      final snapshot = TripSnapshotEnvelope.fromJson(_decodeBody(response.body));
      if (snapshot.tripId != tripController.trip?.id) throw StateError('Snapshot belongs to another trip.');
      await tripController.replaceFromSyncSnapshot(snapshot.snapshot);
      _canonicalRevision = snapshot.revision;
      _memberOnline = true;
      _lastError = null;
      _lastSyncAt = DateTime.now();
      notifyListeners();
    } catch (error) {
      _memberOnline = false;
      _lastError = '$error';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> createExpense({
    required String title,
    required int totalMinor,
    required List<ExpensePayer> payers,
    required List<ExpenseAllocation> allocations,
  }) async {
    if (_mode != MobileSyncMode.member) {
      return tripController.addExpense(
        title: title,
        totalMinor: totalMinor,
        payers: payers,
        allocations: allocations,
      );
    }
    await _submitMemberOperation(
      SyncOperationType.createExpense,
      {
        'title': title,
        'totalMinor': totalMinor,
        'payers': {for (final payer in payers) payer.memberId: payer.amount.minorUnits},
        'allocations': {for (final allocation in allocations) allocation.memberId: allocation.amount.minorUnits},
      },
    );
  }

  Future<void> updateExpense({
    required String expenseId,
    required String title,
    required int totalMinor,
    required List<ExpensePayer> payers,
    required List<ExpenseAllocation> allocations,
  }) async {
    if (_mode != MobileSyncMode.member) {
      return tripController.updateExpense(
        expenseId: expenseId,
        title: title,
        totalMinor: totalMinor,
        payers: payers,
        allocations: allocations,
      );
    }
    await _submitMemberOperation(
      SyncOperationType.updateExpense,
      {
        'expenseId': expenseId,
        'title': title,
        'totalMinor': totalMinor,
        'payers': {for (final payer in payers) payer.memberId: payer.amount.minorUnits},
        'allocations': {for (final allocation in allocations) allocation.memberId: allocation.amount.minorUnits},
      },
    );
  }

  Future<void> deleteExpense(String expenseId) async {
    if (_mode != MobileSyncMode.member) return tripController.removeExpense(expenseId);
    await _submitMemberOperation(SyncOperationType.deleteExpense, {'expenseId': expenseId});
  }

  Future<void> _submitMemberOperation(SyncOperationType type, Map<String, Object?> payload) async {
    final trip = tripController.trip;
    final baseUri = _memberBaseUri;
    final token = _memberSessionToken;
    final actor = _memberId;
    if (trip == null || baseUri == null || token == null || actor == null) {
      throw StateError('No active member sync session.');
    }
    final operation = SyncOperation(
      operationId: _uuid.v4(),
      tripId: trip.id,
      actorMemberId: actor,
      expectedTripRevision: _canonicalRevision,
      type: type,
      payload: payload,
      createdAtEpochMs: DateTime.now().millisecondsSinceEpoch,
    );

    _setBusy(true);
    try {
      final response = await _client.post(
        baseUri.resolve('/v1/operations'),
        headers: {
          'authorization': 'Bearer $token',
          'content-type': 'application/json',
        },
        body: jsonEncode(operation.toJson()),
      ).timeout(const Duration(seconds: 8));
      final body = _decodeBody(response.body);
      if (response.statusCode == 401) throw StateError('Host session expired. Ask for a new invite.');
      if (response.statusCode == 403) throw StateError('This member is not allowed to perform that operation.');
      final result = SyncOperationResult.fromJson(body);
      if (result.status == SyncResultStatus.conflict) {
        _canonicalRevision = result.canonicalTripRevision;
        await refreshMemberSnapshot();
        throw SyncConflictException(result.message ?? 'The crew changed on the host. Review the refreshed data and retry.');
      }
      if (result.status == SyncResultStatus.rejected) {
        throw StateError(result.message ?? result.errorCode ?? 'Host rejected the operation.');
      }
      _canonicalRevision = result.canonicalTripRevision;
      await refreshMemberSnapshot();
    } on TimeoutException {
      _memberOnline = false;
      _lastError = 'Host did not respond. Keep the app open and retry when both phones are on the same network.';
      notifyListeners();
      rethrow;
    } on SocketException catch (error) {
      _memberOnline = false;
      _lastError = 'Host is unreachable: $error';
      notifyListeners();
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(_pollEvents());
    });
  }

  Future<void> _pollEvents() async {
    if (_mode != MobileSyncMode.member || _busy) return;
    final baseUri = _memberBaseUri;
    final token = _memberSessionToken;
    if (baseUri == null || token == null) return;
    try {
      final uri = baseUri.resolve('/v1/events?afterRevision=$_canonicalRevision');
      final response = await _client.get(
        uri,
        headers: {'authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 5));
      if (response.statusCode == 401) throw StateError('Host session expired.');
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
    } catch (error) {
      _memberOnline = false;
      _lastError = '$error';
      notifyListeners();
    }
  }

  Future<void> _restoreMemberSession() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || !tripController.hasTrip) return;
    try {
      final json = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      _memberBaseUri = Uri.parse(json['baseUri'] as String);
      _memberSessionToken = json['sessionToken'] as String;
      _memberId = json['memberId'] as String;
      _pinnedHostId = json['hostId'] as String;
      _canonicalRevision = json['revision'] as int? ?? tripController.trip!.version;
      _mode = MobileSyncMode.member;
      await refreshMemberSnapshot();
      _startPolling();
    } catch (error) {
      _memberOnline = false;
      _mode = MobileSyncMode.local;
      _lastError = 'Saved host session could not be restored: $error';
    }
  }

  Future<void> _persistMemberSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode({
        'baseUri': _memberBaseUri.toString(),
        'sessionToken': _memberSessionToken,
        'memberId': _memberId,
        'hostId': _pinnedHostId,
        'revision': _canonicalRevision,
      }),
    );
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
    final parts = value.split('.').map(int.tryParse).toList();
    if (parts.length != 4 || parts.any((part) => part == null)) return false;
    final a = parts[0]!;
    final b = parts[1]!;
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
    unawaited(_hostServer?.stop() ?? Future.value());
    _client.close();
    super.dispose();
  }
}

final class SyncConflictException implements Exception {
  const SyncConflictException(this.message);

  final String message;

  @override
  String toString() => message;
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
    return switch (type) {
      SyncOperationType.createExpense ||
      SyncOperationType.updateExpense ||
      SyncOperationType.deleteExpense ||
      SyncOperationType.renameMember ||
      SyncOperationType.updatePaymentAccount ||
      SyncOperationType.markSettlement => true,
      SyncOperationType.addMember => false,
    };
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
        if (expense == null) return;
        if (!isOwner && expense.createdByMemberId != actor.id) {
          throw const _ForbiddenOperation('Members may only delete expenses they created.');
        }
        await controller.removeExpense(expenseId);
      case SyncOperationType.addMember:
        if (!isOwner) throw const _ForbiddenOperation('Only the owner can add members.');
        await controller.addMember(payload['name'] as String);
      case SyncOperationType.renameMember:
        final memberId = payload['memberId'] as String;
        if (!isOwner && memberId != actor.id) {
          throw const _ForbiddenOperation('Members may only rename their own profile.');
        }
        await controller.renameMember(memberId, payload['name'] as String);
      case SyncOperationType.updatePaymentAccount:
        final memberId = payload['memberId'] as String;
        if (!isOwner && memberId != actor.id) {
          throw const _ForbiddenOperation('Members may only update their own payment profile.');
        }
        await controller.upsertPaymentAccount(
          memberId: memberId,
          holderName: payload['holderName'] as String,
          bankBin: payload['bankBin'] as String,
          accountIdentifier: payload['accountIdentifier'] as String,
        );
      case SyncOperationType.markSettlement:
        throw const _ForbiddenOperation('Settlement acknowledgements are not enabled in this sync slice yet.');
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
      // Receipt files stay on the device that captured them until media sync is added.
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
