enum TripMemberRole { owner, admin, member }

enum TripMemberStatus { active, removed }

final class TripMember {
  const TripMember({
    required this.id,
    required this.tripId,
    required this.displayName,
    required this.role,
    this.status = TripMemberStatus.active,
    this.version = 0,
  })  : assert(id != ''),
        assert(tripId != ''),
        assert(displayName != ''),
        assert(version >= 0);

  final String id;
  final String tripId;
  final String displayName;
  final TripMemberRole role;
  final TripMemberStatus status;
  final int version;

  bool get isActive => status == TripMemberStatus.active;
}
