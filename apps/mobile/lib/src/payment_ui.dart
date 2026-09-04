import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:splitcrew_domain/splitcrew_domain.dart';
import 'package:splitcrew_payment_qr/splitcrew_payment_qr.dart';

import 'app_state.dart';
import 'home_page.dart';

final class TripWorkspace extends StatelessWidget {
  const TripWorkspace({super.key, required this.controller});

  final TripController controller;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        TripDashboard(controller: controller),
        Positioned(
          left: 16,
          bottom: 16,
          child: SafeArea(
            child: FloatingActionButton.small(
              heroTag: 'payment-center',
              tooltip: 'Payments & QR',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => PaymentCenterPage(controller: controller),
                ),
              ),
              child: const Icon(Icons.qr_code_2_rounded),
            ),
          ),
        ),
      ],
    );
  }
}

final class PaymentCenterPage extends StatelessWidget {
  const PaymentCenterPage({super.key, required this.controller});

  final TripController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final trip = controller.trip!;
        final transfers = controller.settlements;
        return Scaffold(
          appBar: AppBar(title: const Text('Payments & QR')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Text('Payment profiles', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              const Text(
                'Only transfer-routing data is stored locally. SplitCrew never asks for a banking password, PIN, OTP, or login token.',
              ),
              const SizedBox(height: 10),
              for (final member in trip.members)
                _PaymentProfileCard(controller: controller, member: member),
              const SizedBox(height: 24),
              Text('Suggested repayments', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              const Text('QR amount is generated directly from the deterministic settlement result.'),
              const SizedBox(height: 10),
              if (transfers.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Everyone is settled. No repayment QR is needed.'),
                  ),
                )
              else
                for (final transfer in transfers)
                  _SettlementQrCard(controller: controller, transfer: transfer),
            ],
          ),
        );
      },
    );
  }
}

final class _PaymentProfileCard extends StatelessWidget {
  const _PaymentProfileCard({required this.controller, required this.member});

  final TripController controller;
  final StoredMember member;

  @override
  Widget build(BuildContext context) {
    final account = controller.paymentAccountForMember(member.id);
    final bank = account == null ? null : VietQrPayloadProvider.bankByBin(account.routingIdentifier);
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Text(member.name.isEmpty ? '?' : member.name[0].toUpperCase())),
        title: Text(member.name),
        subtitle: account == null
            ? const Text('No repayment account')
            : Text('${bank?.displayName ?? account.routingIdentifier} · ${_maskAccount(account.accountIdentifier)}\n${account.holderName}'),
        isThreeLine: account != null,
        trailing: PopupMenuButton<String>(
          onSelected: (value) async {
            if (value == 'edit') {
              await _showPaymentAccountDialog(context, controller, member);
            } else if (value == 'remove') {
              await controller.removePaymentAccount(member.id);
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(value: 'edit', child: Text(account == null ? 'Set up' : 'Edit')),
            if (account != null) const PopupMenuItem(value: 'remove', child: Text('Remove')),
          ],
        ),
        onTap: () => _showPaymentAccountDialog(context, controller, member),
      ),
    );
  }
}

final class _SettlementQrCard extends StatelessWidget {
  const _SettlementQrCard({required this.controller, required this.transfer});

  final TripController controller;
  final dynamic transfer;

  @override
  Widget build(BuildContext context) {
    final account = controller.paymentAccountForMember(transfer.toMemberId as String);
    final amount = transfer.amount as Money;
    return Card(
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.arrow_forward_rounded)),
        title: Text(
          '${controller.memberName(transfer.fromMemberId as String)} → ${controller.memberName(transfer.toMemberId as String)}',
        ),
        subtitle: Text(
          account == null
              ? 'Set up ${controller.memberName(transfer.toMemberId as String)} payment account to generate QR.'
              : '${_money(amount.minorUnits)} ₫ · fixed VietQR amount',
        ),
        trailing: account == null
            ? const Icon(Icons.qr_code_2_rounded)
            : FilledButton.tonalIcon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => RepaymentQrPage(
                      controller: controller,
                      fromMemberId: transfer.fromMemberId as String,
                      toMemberId: transfer.toMemberId as String,
                      amount: amount,
                    ),
                  ),
                ),
                icon: const Icon(Icons.qr_code_2_rounded),
                label: const Text('QR'),
              ),
      ),
    );
  }
}

final class RepaymentQrPage extends StatelessWidget {
  const RepaymentQrPage({
    super.key,
    required this.controller,
    required this.fromMemberId,
    required this.toMemberId,
    required this.amount,
  });

  final TripController controller;
  final String fromMemberId;
  final String toMemberId;
  final Money amount;

  @override
  Widget build(BuildContext context) {
    final account = controller.paymentAccountForMember(toMemberId);
    if (account == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Repayment QR')),
        body: const Center(child: Text('Recipient payment account is missing.')),
      );
    }
    final bank = VietQrPayloadProvider.bankByBin(account.routingIdentifier);
    final purpose = _paymentPurpose(controller.trip!.id);
    String? payload;
    Object? error;
    try {
      payload = const VietQrPayloadProvider().buildPayload(
        account: account,
        amount: amount,
        purpose: purpose,
      );
    } catch (caught) {
      error = caught;
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Repayment QR')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            '${controller.memberName(fromMemberId)} pays ${controller.memberName(toMemberId)}',
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            '${_money(amount.minorUnits)} ₫',
            style: Theme.of(context).textTheme.headlineMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          if (payload != null)
            Center(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: QrImageView(data: payload, version: QrVersions.auto, size: 280),
                ),
              ),
            )
          else
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Unable to generate VietQR: $error'),
              ),
            ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DetailRow(label: 'Bank', value: bank?.displayName ?? account.routingIdentifier),
                  _DetailRow(label: 'Account', value: account.accountIdentifier),
                  _DetailRow(label: 'Holder', value: account.holderName),
                  _DetailRow(label: 'Amount', value: '${_money(amount.minorUnits)} VND'),
                  _DetailRow(label: 'Content', value: purpose),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Verify the recipient and amount in the banking app before confirming the transfer. SplitCrew does not mark a payment received automatically.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

final class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 88, child: Text(label, style: Theme.of(context).textTheme.labelLarge)),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}

Future<void> _showPaymentAccountDialog(
  BuildContext context,
  TripController controller,
  StoredMember member,
) async {
  final existing = controller.paymentAccountForMember(member.id);
  final banks = VietQrPayloadProvider.supportedBanks;
  var selectedBin = existing?.routingIdentifier;
  if (selectedBin == null || !banks.any((bank) => bank.binCode == selectedBin)) {
    selectedBin = banks.first.binCode;
  }
  final holderController = TextEditingController(text: existing?.holderName ?? member.name.toUpperCase());
  final accountController = TextEditingController(text: existing?.accountIdentifier ?? '');
  try {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text('Payment account · ${member.name}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedBin,
                  decoration: const InputDecoration(labelText: 'Bank'),
                  items: [
                    for (final bank in banks)
                      DropdownMenuItem(value: bank.binCode, child: Text('${bank.displayName} (${bank.binCode})')),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => selectedBin = value);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: accountController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Account number'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: holderController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'Account holder name'),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Do not enter a password, PIN, OTP, card CVV, or banking login credential.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                try {
                  await controller.upsertPaymentAccount(
                    memberId: member.id,
                    holderName: holderController.text,
                    bankBin: selectedBin!,
                    accountIdentifier: accountController.text,
                  );
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                } catch (error) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text(error.toString())));
                  }
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  } finally {
    holderController.dispose();
    accountController.dispose();
  }
}

String _paymentPurpose(String tripId) {
  final compact = tripId.replaceAll('-', '').toUpperCase();
  final suffix = compact.length <= 10 ? compact : compact.substring(0, 10);
  return 'SPLITCREW $suffix';
}

String _maskAccount(String value) {
  if (value.length <= 4) return value;
  return '${List.filled(value.length - 4, '•').join()}${value.substring(value.length - 4)}';
}

String _money(int value) {
  final negative = value < 0;
  final digits = value.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
    buffer.write(digits[i]);
  }
  return '${negative ? '-' : ''}$buffer';
}
