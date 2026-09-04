import 'package:splitcrew_domain/splitcrew_domain.dart';
import 'package:vietqr_core/vietqr_core.dart';

final class PaymentQrBank {
  const PaymentQrBank({required this.binCode, required this.displayName});

  final String binCode;
  final String displayName;
}

abstract interface class PaymentQrPayloadProvider {
  String buildPayload({
    required PaymentAccount account,
    required Money amount,
    required String purpose,
  });
}

/// VietQR/EMVCo payload adapter.
///
/// The external codec is isolated behind [PaymentQrPayloadProvider] so it can
/// be replaced without changing SplitCrew domain or UI code.
final class VietQrPayloadProvider implements PaymentQrPayloadProvider {
  const VietQrPayloadProvider();

  static List<PaymentQrBank> get supportedBanks => List.unmodifiable(
        SupportedBank.values.map(
          (bank) => PaymentQrBank(binCode: bank.binCode, displayName: bank.displayName),
        ),
      );

  static PaymentQrBank? bankByBin(String binCode) {
    final bank = SupportedBank.fromBinCode(binCode);
    return bank == null ? null : PaymentQrBank(binCode: bank.binCode, displayName: bank.displayName);
  }

  @override
  String buildPayload({
    required PaymentAccount account,
    required Money amount,
    required String purpose,
  }) {
    if (account.provider != PaymentAccountProvider.vietQrBank) {
      throw ArgumentError('Payment account is not a VietQR bank account.');
    }
    if (amount.currencyCode != 'VND') {
      throw ArgumentError('VietQR repayment currently requires VND.');
    }
    if (amount.minorUnits <= 0) {
      throw ArgumentError('Repayment amount must be greater than zero.');
    }
    final bank = SupportedBank.fromBinCode(account.routingIdentifier);
    if (bank == null) {
      throw ArgumentError('Unsupported VietQR bank BIN: ${account.routingIdentifier}');
    }
    final cleanPurpose = _normalizePurpose(purpose);
    final data = VietQrData(
      bankBinCode: bank,
      bankAccount: account.accountIdentifier.trim(),
      amount: amount.minorUnits.toString(),
      merchantName: account.holderName.trim(),
      additional: AdditionalData(purpose: cleanPurpose),
    );
    final encoded = VietQr.encode(data);

    // Fail closed if the codec cannot round-trip the routing-critical fields.
    final decoded = VietQr.decode(encoded);
    final beneficiary = decoded.merchantAccInfo.beneficiaryOrgData;
    if (decoded.amount != amount.minorUnits.toString() ||
        beneficiary.bankBinCode != account.routingIdentifier ||
        beneficiary.bankAccount != account.accountIdentifier.trim()) {
      throw StateError('VietQR payload round-trip validation failed.');
    }
    return encoded;
  }

  String _normalizePurpose(String input) {
    final normalized = input
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9 _-]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.isEmpty) return 'SPLITCREW';
    return normalized.length <= 25 ? normalized : normalized.substring(0, 25).trim();
  }
}
