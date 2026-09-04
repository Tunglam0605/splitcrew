import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:splitcrew_local_host/splitcrew_local_host.dart';
import 'package:splitcrew_sync_protocol/splitcrew_sync_protocol.dart';
import 'package:test/test.dart';

final class TestBackend implements HostTripBackend {
  TestBackend() : _ledger = SyncRevisionLedger(tripId: 'trip-1');

  final SyncRevisionLedger _ledger;
  final Map<String, Object?> state = {'name': 'Test trip'};

  @override
  String get tripId => 'trip-1';

  @override
  int get revision => _ledger.revision;

  @override
  bool canSubmit({required String memberId, required SyncOperationType type}) => memberId == 'member-1';

  @override
  Future<TripSnapshotEnvelope> snapshot() async => TripSnapshotEnvelope(
        tripId: tripId,
        revision: revision,
        snapshot: state,
      );

  @override
  Future<SyncOperationResult> apply(SyncOperation operation) async {
    final evaluated = _ledger.evaluate(operation);
    if (evaluated.status != SyncResultStatus.accepted) return evaluated;
    state['lastOperation'] = operation.operationId;
    return _ledger.commit(
      operation: operation,
      eventId: 'event-${operation.operationId}',
      canonicalPayload: {'lastOperation': operation.operationId},
      committedAtEpochMs: DateTime.now().millisecondsSinceEpoch,
    );
  }
}

void main() {
  late LocalHostServer host;
  late TestBackend backend;
  late Uri base;

  setUp(() async {
    backend = TestBackend();
    host = LocalHostServer(backend: backend, hostId: 'host-1');
    await host.start(address: InternetAddress.loopbackIPv4);
    base = Uri.parse('http://127.0.0.1:${host.port}');
  });

  tearDown(() => host.stop());

  test('health exposes pinned host identity without a session', () async {
    final response = await http.get(base.resolve('/v1/health'));
    expect(response.statusCode, 200);
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    expect(json['hostId'], 'host-1');
    expect(json['tripId'], 'trip-1');
  });

  test('invite is single-use and grants canonical snapshot session', () async {
    final invite = host.createInvite(
      memberId: 'member-1',
      advertisedHost: '127.0.0.1',
    );
    final first = await http.post(
      base.resolve('/v1/join'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'invite': invite.encode()}),
    );
    expect(first.statusCode, 200);
    final joined = jsonDecode(first.body) as Map<String, dynamic>;
    expect(joined['memberId'], 'member-1');
    expect((joined['snapshot'] as Map<String, dynamic>)['revision'], 0);

    final second = await http.post(
      base.resolve('/v1/join'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'invite': invite.encode()}),
    );
    expect(second.statusCode, 409);
  });

  test('authenticated operation commits once and stale revision conflicts', () async {
    final invite = host.createInvite(memberId: 'member-1', advertisedHost: '127.0.0.1');
    final join = await http.post(
      base.resolve('/v1/join'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'invite': invite.encode()}),
    );
    final token = (jsonDecode(join.body) as Map<String, dynamic>)['sessionToken'] as String;
    final headers = {
      'content-type': 'application/json',
      'authorization': 'Bearer $token',
    };
    final operation = SyncOperation(
      operationId: 'op-1',
      tripId: 'trip-1',
      actorMemberId: 'member-1',
      expectedTripRevision: 0,
      type: SyncOperationType.createExpense,
      payload: const {'title': 'Dinner'},
      createdAtEpochMs: 1000,
    );

    final accepted = await http.post(
      base.resolve('/v1/operations'),
      headers: headers,
      body: jsonEncode(operation.toJson()),
    );
    expect(accepted.statusCode, 200);
    expect((jsonDecode(accepted.body) as Map<String, dynamic>)['canonicalTripRevision'], 1);

    final duplicate = await http.post(
      base.resolve('/v1/operations'),
      headers: headers,
      body: jsonEncode(operation.toJson()),
    );
    expect(duplicate.statusCode, 200);
    expect((jsonDecode(duplicate.body) as Map<String, dynamic>)['status'], 'duplicate');

    final stale = SyncOperation(
      operationId: 'op-2',
      tripId: 'trip-1',
      actorMemberId: 'member-1',
      expectedTripRevision: 0,
      type: SyncOperationType.createExpense,
      payload: const {'title': 'Taxi'},
      createdAtEpochMs: 1001,
    );
    final conflict = await http.post(
      base.resolve('/v1/operations'),
      headers: headers,
      body: jsonEncode(stale.toJson()),
    );
    expect(conflict.statusCode, 409);
    expect((jsonDecode(conflict.body) as Map<String, dynamic>)['status'], 'conflict');

    final events = await http.get(
      base.resolve('/v1/events?afterRevision=0'),
      headers: {'authorization': 'Bearer $token'},
    );
    final eventJson = jsonDecode(events.body) as Map<String, dynamic>;
    expect((eventJson['events'] as List), hasLength(1));
  });
}
