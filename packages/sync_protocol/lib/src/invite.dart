import 'dart:convert';

final class LocalHostInvite {
  const LocalHostInvite({
    required this.tripId,
    required this.memberId,
    required this.hostId,
    required this.host,
    required this.port,
    required this.token,
    required this.expiresAtEpochMs,
    this.protocolVersion = 1,
  });

  final int protocolVersion;
  final String tripId;
  final String memberId;
  final String hostId;
  final String host;
  final int port;
  final String token;
  final int expiresAtEpochMs;

  bool isExpiredAt(int nowEpochMs) => nowEpochMs >= expiresAtEpochMs;

  Uri get baseUri => Uri(scheme: 'http', host: host, port: port);

  Map<String, Object?> toJson() => {
        'protocolVersion': protocolVersion,
        'tripId': tripId,
        'memberId': memberId,
        'hostId': hostId,
        'host': host,
        'port': port,
        'token': token,
        'expiresAtEpochMs': expiresAtEpochMs,
      };

  String encode() {
    final bytes = utf8.encode(jsonEncode(toJson()));
    return 'splitcrew://join/${base64Url.encode(bytes).replaceAll('=', '')}';
  }

  factory LocalHostInvite.decode(String encoded) {
    final uri = Uri.parse(encoded);
    if (uri.scheme != 'splitcrew' || uri.host != 'join' || uri.pathSegments.length != 1) {
      throw const FormatException('Invalid SplitCrew invite URI.');
    }
    final segment = uri.pathSegments.single;
    final normalized = segment.padRight((segment.length + 3) ~/ 4 * 4, '=');
    final decoded = jsonDecode(utf8.decode(base64Url.decode(normalized)));
    if (decoded is! Map) throw const FormatException('Invalid invite payload.');
    final json = Map<String, dynamic>.from(decoded);
    final invite = LocalHostInvite(
      protocolVersion: json['protocolVersion'] as int? ?? 1,
      tripId: json['tripId'] as String,
      memberId: json['memberId'] as String,
      hostId: json['hostId'] as String,
      host: json['host'] as String,
      port: json['port'] as int,
      token: json['token'] as String,
      expiresAtEpochMs: json['expiresAtEpochMs'] as int,
    );
    if (invite.protocolVersion != 1 ||
        invite.tripId.trim().isEmpty ||
        invite.memberId.trim().isEmpty ||
        invite.hostId.trim().isEmpty ||
        invite.host.trim().isEmpty ||
        invite.token.length < 32 ||
        invite.port <= 0 ||
        invite.port > 65535) {
      throw const FormatException('Invalid SplitCrew invite fields.');
    }
    return invite;
  }
}
