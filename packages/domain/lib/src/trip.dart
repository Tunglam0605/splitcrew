final class Trip {
  const Trip({
    required this.id,
    required this.name,
    required this.currencyCode,
    required this.ownerMemberId,
    this.revision = 0,
  })  : assert(id != ''),
        assert(name != ''),
        assert(currencyCode.length == 3),
        assert(ownerMemberId != ''),
        assert(revision >= 0);

  final String id;
  final String name;
  final String currencyCode;
  final String ownerMemberId;
  final int revision;
}
