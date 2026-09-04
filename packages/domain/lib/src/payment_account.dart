enum PaymentAccountProvider { vietQrBank }

/// A safe repayment destination owned by a trip member.
///
/// This model intentionally contains only public transfer-routing data.
/// Passwords, PINs, OTPs, access tokens, and banking session credentials must
/// never be stored in SplitCrew.
final class PaymentAccount {
  PaymentAccount({
    required this.id,
    required this.memberId,
    required this.provider,
    required this.holderName,
    required this.routingIdentifier,
    required this.accountIdentifier,
    this.version = 0,
  }) {
    if (id.trim().isEmpty || memberId.trim().isEmpty) {
      throw ArgumentError('Payment account identity and member are required.');
    }
    if (holderName.trim().isEmpty) {
      throw ArgumentError('Account holder name is required.');
    }
    if (routingIdentifier.trim().isEmpty) {
      throw ArgumentError('Routing identifier is required.');
    }
    if (accountIdentifier.trim().isEmpty) {
      throw ArgumentError('Account identifier is required.');
    }
    if (version < 0) {
      throw ArgumentError.value(version, 'version', 'must be >= 0');
    }
  }

  final String id;
  final String memberId;
  final PaymentAccountProvider provider;
  final String holderName;
  final String routingIdentifier;
  final String accountIdentifier;
  final int version;
}
