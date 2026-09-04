import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:splitcrew_sync_protocol/splitcrew_sync_protocol.dart';
import 'package:uuid/uuid.dart';

import 'host_backend.dart';
import 'invite_registry.dart';

final class LocalHostServer {
  LocalHostServer({
    required this.backend,
    InviteRegistry? invites,
    String? hostId,
    Random? random,
  })  : invites = invites ?? InviteRegistry(random: random),
        hostId = hostId ?? const Uuid().v4(),
        _random = random ?? Random.secure();

  final HostTripBackend backend;
  final InviteRegistry invites;
  final String hostId;
  final Random _random;

  HttpServer? _server;
  final Map<String, _HostSession> _sessions = {};
  final List<CommittedSyncEvent> _events = [];

  bool get isRunning => _server != null;
  int? get port => _server?.port;

  Future<void> start({InternetAddress? address, int port = 0}) async {
    if (_server != null) throw StateError('Local host is already running.');
    final router = Router()
      ..get('/v1/health', _health)
      ..post('/v1/join', _join)
      ..get('/v1/snapshot', _snapshot)
      ..post('/v1/operations', _operation)
      ..get('/v1/events', _eventFeed);
    final handler = const Pipeline()
        .addMiddleware(_corsForLan())
        .addMiddleware(_jsonErrorBoundary())
        .addHandler(router.call);
    _server = await shelf_io.serve(
      handler,
      address ?? InternetAddress.anyIPv4,
      port,
      shared: false,
    );
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _sessions.clear();
    if (server != null) await server.close(force: true);
  }

  LocalHostInvite createInvite({
    required String memberId,
    required String advertisedHost,
    Duration ttl = const Duration(minutes: 10),
  }) {
    final boundPort = _server?.port;
    if (boundPort == null) throw StateError('Start the local host before creating an invite.');
    return invites.issue(
      tripId: backend.tripId,
      memberId: memberId,
      hostId: hostId,
      advertisedHost: advertisedHost,
      port: boundPort,
      nowEpochMs: DateTime.now().millisecondsSinceEpoch,
      ttl: ttl,
    );
  }

  Response _health(Request request) => _json(200, {
        'protocolVersion': 1,
        'hostId': hostId,
        'tripId': backend.tripId,
        'revision': backend.revision,
      });

  Future<Response> _join(Request request) async {
    final body = await _readJson(request);
    final encoded = body['invite'] as String?;
    if (encoded == null) return _json(400, {'error': 'INVITE_REQUIRED'});
    LocalHostInvite invite;
    try {
      invite = LocalHostInvite.decode(encoded);
    } on FormatException {
      return _json(400, {'error': 'INVITE_INVALID'});
    }
    if (invite.hostId != hostId || invite.tripId != backend.tripId) {
      return _json(409, {'error': 'HOST_OR_TRIP_MISMATCH'});
    }
    final redemption = invites.redeem(
      invite,
      nowEpochMs: DateTime.now().millisecondsSinceEpoch,
    );
    if (!redemption.accepted) {
      return _json(409, {'error': redemption.errorCode});
    }
    final sessionToken = _randomToken(32);
    _sessions[sessionToken] = _HostSession(memberId: redemption.memberId!);
    final snapshot = await backend.snapshot();
    return _json(200, {
      'sessionToken': sessionToken,
      'memberId': redemption.memberId,
      'hostId': hostId,
      'snapshot': snapshot.toJson(),
    });
  }

  Future<Response> _snapshot(Request request) async {
    final session = _authenticate(request);
    if (session == null) return _json(401, {'error': 'UNAUTHORIZED'});
    final snapshot = await backend.snapshot();
    return _json(200, snapshot.toJson());
  }

  Future<Response> _operation(Request request) async {
    final session = _authenticate(request);
    if (session == null) return _json(401, {'error': 'UNAUTHORIZED'});
    final body = await _readJson(request);
    SyncOperation operation;
    try {
      operation = SyncOperation.fromJson(body);
    } on Object catch (error) {
      return _json(400, {'error': 'OPERATION_INVALID', 'message': '$error'});
    }
    if (operation.actorMemberId != session.memberId) {
      return _json(403, {'error': 'ACTOR_SESSION_MISMATCH'});
    }
    if (!backend.canSubmit(memberId: session.memberId, type: operation.type)) {
      return _json(403, {'error': 'OPERATION_FORBIDDEN'});
    }
    final result = await backend.apply(operation);
    final event = result.event;
    if (event != null && !_events.any((existing) => existing.eventId == event.eventId)) {
      _events.add(event);
      if (_events.length > 500) _events.removeRange(0, _events.length - 500);
    }
    final statusCode = switch (result.status) {
      SyncResultStatus.accepted || SyncResultStatus.duplicate => 200,
      SyncResultStatus.conflict => 409,
      SyncResultStatus.rejected => 422,
    };
    return _json(statusCode, result.toJson());
  }

  Response _eventFeed(Request request) {
    final session = _authenticate(request);
    if (session == null) return _json(401, {'error': 'UNAUTHORIZED'});
    final after = int.tryParse(request.url.queryParameters['afterRevision'] ?? '') ?? -1;
    final events = _events.where((event) => event.revision > after).map((event) => event.toJson()).toList();
    return _json(200, {
      'canonicalTripRevision': backend.revision,
      'events': events,
    });
  }

  _HostSession? _authenticate(Request request) {
    final header = request.headers['authorization'];
    if (header == null || !header.startsWith('Bearer ')) return null;
    return _sessions[header.substring(7).trim()];
  }

  Future<Map<String, dynamic>> _readJson(Request request) async {
    final raw = await request.readAsString();
    if (raw.isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(raw);
    if (decoded is! Map) throw const FormatException('JSON object required.');
    return Map<String, dynamic>.from(decoded);
  }

  String _randomToken(int byteCount) {
    final bytes = List<int>.generate(byteCount, (_) => _random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static Response _json(int statusCode, Object body) => Response(
        statusCode,
        body: jsonEncode(body),
        headers: const {'content-type': 'application/json; charset=utf-8'},
      );

  static Middleware _corsForLan() => (innerHandler) => (request) async {
        if (request.method == 'OPTIONS') {
          return Response.ok('', headers: _corsHeaders);
        }
        final response = await innerHandler(request);
        return response.change(headers: {...response.headers, ..._corsHeaders});
      };

  static Middleware _jsonErrorBoundary() => (innerHandler) => (request) async {
        try {
          return await innerHandler(request);
        } on FormatException catch (error) {
          return _json(400, {'error': 'BAD_REQUEST', 'message': error.message});
        } catch (_) {
          return _json(500, {'error': 'INTERNAL_ERROR'});
        }
      };

  static const _corsHeaders = {
    'access-control-allow-origin': '*',
    'access-control-allow-headers': 'authorization, content-type',
    'access-control-allow-methods': 'GET, POST, OPTIONS',
  };
}

final class _HostSession {
  const _HostSession({required this.memberId});

  final String memberId;
}
