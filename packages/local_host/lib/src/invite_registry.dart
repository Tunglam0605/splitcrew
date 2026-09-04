import 'dart:convert';
import 'dart:math';

import 'package:splitcrew_sync_protocol/splitcrew_sync_protocol.dart';

final class InviteRegistry {
  InviteRegistry({Random? random}) : _random = random ?? Random.secure();

  final Random _random;
  final Map<String, _InviteRecord> _records = {};

  LocalHostInvite issue({
    required String tripId,
    required String memberId,
    required String hostId,
    required String advertisedHost,
    required int port,
    required int nowEpochMs,
    Duration ttl = const Duration(minutes: 10),
  }) {
    if (ttl <= Duration.zero) throw ArgumentError('Invite TTL must be positive.');
    final token = _randomToken(32);
    final invite = LocalHostInvite(
      tripId: tripId,
      memberId: memberId,
      hostId: hostId,
      host: advertisedHost,
      port: port,
      token: token,
      expiresAtEpochMs: nowEpochMs + ttl.inMilliseconds,
    );
    _records[token] = _InviteRecord(invite: invite);
    return invite;
  }

  InviteRedemption redeem(LocalHostInvite presented, {required int nowEpochMs}) {
    final record = _records[presented.token];
    if (record == null) return const InviteRedemption.rejected('INVITE_UNKNOWN');
    if (record.used) return const InviteRedemption.rejected('INVITE_ALREADY_USED');
    if (record.invite.isExpiredAt(nowEpochMs)) {
      _records.remove(presented.token);
      return const InviteRedemption.rejected('INVITE_EXPIRED');
    }
    if (!_sameInvite(record.invite, presented)) {
      return const InviteRedemption.rejected('INVITE_MISMATCH');
    }
    record.used = true;
    return InviteRedemption.accepted(memberId: record.invite.memberId);
  }

  bool _sameInvite(LocalHostInvite expected, LocalHostInvite actual) =>
      expected.protocolVersion == actual.protocolVersion &&
      expected.tripId == actual.tripId &&
      expected.memberId == actual.memberId &&
      expected.hostId == actual.hostId &&
      expected.host == actual.host &&
      expected.port == actual.port &&
      expected.token == actual.token &&
      expected.expiresAtEpochMs == actual.expiresAtEpochMs;

  String _randomToken(int byteCount) {
    final bytes = List<int>.generate(byteCount, (_) => _random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}

final class InviteRedemption {
  const InviteRedemption._({required this.accepted, this.memberId, this.errorCode});

  const InviteRedemption.accepted({required String memberId})
      : this._(accepted: true, memberId: memberId);

  const InviteRedemption.rejected(String errorCode)
      : this._(accepted: false, errorCode: errorCode);

  final bool accepted;
  final String? memberId;
  final String? errorCode;
}

final class _InviteRecord {
  _InviteRecord({required this.invite});

  final LocalHostInvite invite;
  bool used = false;
}
