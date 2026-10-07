import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:splitcrew_domain/splitcrew_domain.dart';
import 'package:splitcrew_payment_qr/splitcrew_payment_qr.dart';
import 'package:splitcrew_settlement_engine/splitcrew_settlement_engine.dart';

import 'app_state.dart';
import 'home_page.dart';
import 'image_export.dart';
import 'settlement_ui.dart';
import 'sync_service.dart';

final class TripWorkspace extends StatelessWidget {
  const TripWorkspace({super.key, required this.controller, required this.sync});

  final TripController controller;
  final MobileSyncController sync;

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
                  builder: (_) => PaymentCenterPage(controller: controller, sync: sync),
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
  const PaymentCenterPage({super.key, required this.controller, required this.sync});

  final TripController controller;
  final MobileSyncController sync;

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
                  _SettlementQrCard(controller: controller, sync: sync, transfer: transfer),
              const SizedBox(height: 24),
              SettlementHistorySection(controller: controller, showEmpty: true),
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
  const _SettlementQrCard({required this.controller, required this.sync, required this.transfer});

  final TripController controller;
  final MobileSyncController sync;
  final SettlementTransfer transfer;

  @override
  Widget build(BuildContext context) {
    final account = controller.paymentAccountForMember(transfer.toMemberId);
    final amount = transfer.amount;
    return Card(
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.arrow_forward_rounded)),
        title: Text(
          '${controller.memberName(transfer.fromMemberId)} → ${controller.memberName(transfer.toMemberId)}',
        ),
        subtitle: Text(
          account == null
              ? 'Set up ${controller.memberName(transfer.toMemberId)} payment account to generate QR.'
              : '${_money(amount.minorUnits)} ₫ · fixed VietQR amount',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (account != null)
              IconButton(
                tooltip: 'Repayment QR',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => RepaymentQrPage(
                      controller: controller,
                      fromMemberId: transfer.fromMemberId,
                      toMemberId: transfer.toMemberId,
                      amount: amount,
                    ),
                  ),
                ),
                icon: const Icon(Icons.qr_code_2_rounded),
              ),
            IconButton.filledTonal(
              tooltip: 'Record paid',
              onPressed: () => confirmAndRecordSettlement(
                context,
                controller: controller,
                sync: sync,
                transfer: transfer,
              ),
              icon: const Icon(Icons.check_rounded),
            ),
          ],
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
            _ShareableRepaymentQr(
              payload: payload,
              fromName: controller.memberName(fromMemberId),
              toName: controller.memberName(toMemberId),
              amountMinor: amount.minorUnits,
              bankName: bank?.displayName ?? account.routingIdentifier,
              accountIdentifier: account.accountIdentifier,
              holderName: account.holderName,
              purpose: purpose,
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

final class _ShareableRepaymentQr extends StatefulWidget {
  const _ShareableRepaymentQr({
    required this.payload,
    required this.fromName,
    required this.toName,
    required this.amountMinor,
    required this.bankName,
    required this.accountIdentifier,
    required this.holderName,
    required this.purpose,
  });

  final String payload;
  final String fromName;
  final String toName;
  final int amountMinor;
  final String bankName;
  final String accountIdentifier;
  final String holderName;
  final String purpose;

  @override
  State<_ShareableRepaymentQr> createState() => _ShareableRepaymentQrState();
}

final class _ShareableRepaymentQrState extends State<_ShareableRepaymentQr> {
  final GlobalKey _captureKey = GlobalKey();
  final PngExportService _exporter = const PngExportService();
  bool _busy = false;

  Future<void> _save() async {
    await _runExport((bytes) async {
      final saved = await _exporter.savePng(
        bytes: bytes,
        fileName: _fileName(),
        dialogTitle: 'Save repayment QR',
      );
      if (saved && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Repayment QR PNG saved.')),
        );
      }
    });
  }

  Future<void> _share() async {
    await _runExport((bytes) async {
      await _exporter.sharePng(
        bytes: bytes,
        fileName: _fileName(),
        subject: 'SplitCrew repayment QR',
        text: '${widget.fromName} pays ${widget.toName} · '
            '${_money(widget.amountMinor)} VND',
      );
    });
  }

  Future<void> _runExport(Future<void> Function(Uint8List bytes) action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await _exporter.captureBoundary(
        _captureKey,
        targetPixelWidth: 1440,
        maxPixelRatio: 3,
      );
      await action(bytes);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _fileName() {
    final recipient = widget.toName
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '-')
        .replaceAll(RegExp(r'-+'), '-');
    return 'splitcrew-repayment-'
        '${recipient.isEmpty ? 'recipient' : recipient}-'
        '${widget.amountMinor}.png';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        RepaintBoundary(
          key: _captureKey,
          child: Material(
            color: Colors.white,
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 440),
              padding: const EdgeInsets.all(24),
              color: Colors.white,
              child: Column(
                children: [
                  const Text(
                    'SplitCrew repayment',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${widget.fromName} → ${widget.toName}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.black87, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_money(widget.amountMinor)} VND',
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 18),
                  QrImageView(
                    data: widget.payload,
                    version: QrVersions.auto,
                    size: 280,
                    backgroundColor: Colors.white,
                  ),
                  const SizedBox(height: 16),
                  _QrExportDetail(label: 'Bank', value: widget.bankName),
                  _QrExportDetail(label: 'Account', value: widget.accountIdentifier),
                  _QrExportDetail(label: 'Holder', value: widget.holderName),
                  _QrExportDetail(label: 'Content', value: widget.purpose),
                  const SizedBox(height: 12),
                  const Text(
                    'Verify recipient and amount in your banking app before confirming.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: WrapAlignment.center,
          children: [
            FilledButton.tonalIcon(
              onPressed: _busy ? null : _save,
              icon: const Icon(Icons.download_rounded),
              label: Text(_busy ? 'Preparing…' : 'Save QR'),
            ),
            FilledButton.icon(
              onPressed: _busy ? null : _share,
              icon: const Icon(Icons.share_rounded),
              label: const Text('Share QR'),
            ),
          ],
        ),
        if (_busy) ...[
          const SizedBox(height: 10),
          LinearProgressIndicator(color: scheme.primary),
        ],
      ],
    );
  }
}

final class _QrExportDetail extends StatelessWidget {
  const _QrExportDetail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.black54,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.black87, fontSize: 12),
            ),
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
