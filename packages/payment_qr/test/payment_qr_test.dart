import 'package:splitcrew_domain/splitcrew_domain.dart';
import 'package:splitcrew_payment_qr/splitcrew_payment_qr.dart';
import 'package:test/test.dart';
import 'package:vietqr_core/vietqr_core.dart';

void main() {
  const provider = VietQrPayloadProvider();

  test('builds a VietQR payload with exact VND amount and routing data', () {
    final account = PaymentAccount(
      id: 'payment-1',
      memberId: 'lam',
      provider: PaymentAccountProvider.vietQrBank,
      holderName: 'NGUYEN VAN A',
      routingIdentifier: '970422',
      accountIdentifier: '5566778899',
    );
    const amount = Money(minorUnits: 527000, currencyCode: 'VND');
    final payload = provider.buildPayload(
      account: account,
      amount: amount,
      purpose: 'SplitCrew Da Nang 2026',
    );
    expect(payload, isNotEmpty);
    final decoded = VietQr.decode(payload);
    expect(decoded.amount, '527000');
    expect(decoded.merchantAccInfo.beneficiaryOrgData.bankBinCode, '970422');
    expect(decoded.merchantAccInfo.beneficiaryOrgData.bankAccount, '5566778899');
  });

  test('rejects a non-VND repayment', () {
    final account = PaymentAccount(
      id: 'payment-1',
      memberId: 'lam',
      provider: PaymentAccountProvider.vietQrBank,
      holderName: 'NGUYEN VAN A',
      routingIdentifier: '970422',
      accountIdentifier: '5566778899',
    );
    expect(
      () => provider.buildPayload(
        account: account,
        amount: const Money(minorUnits: 100, currencyCode: 'USD'),
        purpose: 'SplitCrew',
      ),
      throwsArgumentError,
    );
  });

  test('exposes supported bank labels without leaking codec types', () {
    final mb = VietQrPayloadProvider.bankByBin('970422');
    expect(mb?.displayName, 'MB Bank');
    expect(VietQrPayloadProvider.supportedBanks, isNotEmpty);
  });
}
