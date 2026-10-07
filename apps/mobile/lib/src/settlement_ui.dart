import 'package:flutter/material.dart';
import 'package:splitcrew_settlement_engine/splitcrew_settlement_engine.dart';

import 'app_state.dart';
import 'sync_service.dart';

Future<void> confirmAndRecordSettlement(
  BuildContext context, {
  required TripController controller,
  required MobileSyncController sync,
  required SettlementTransfer transfer,
}) async {
  final fromName = controller.memberName(transfer.fromMemberId);
  final toName = controller.memberName(transfer.toMemberId);
  final amount = _money(transfer.amount.minorUnits);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Record payment?'),
      content: Text(
        'Record that $fromName paid $toName $amount ${transfer.amount.currencyCode}?\n\n'
        'This changes the canonical settlement ledger and clears this suggested debt after the owner accepts it.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Record paid'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  try {
    final disposition = await sync.markSettlement(
      fromMemberId: transfer.fromMemberId,
      toMemberId: transfer.toMemberId,
      amountMinor: transfer.amount.minorUnits,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          disposition == SyncWriteDisposition.queued
              ? 'Payment acknowledgement queued for owner validation.'
              : 'Payment recorded in the settlement ledger.',
        ),
      ),
    );
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.toString())),
    );
  }
}

final class SettlementHistorySection extends StatelessWidget {
  const SettlementHistorySection({
    super.key,
    required this.controller,
    this.showEmpty = false,
  });

  final TripController controller;
  final bool showEmpty;

  @override
  Widget build(BuildContext context) {
    final items = controller.trip?.settlementAcknowledgements ?? const [];
    if (items.isEmpty && !showEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Settlement history', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        const Text('Append-only records of payments accepted into the canonical crew ledger.'),
        const SizedBox(height: 8),
        if (items.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No settlement payments have been recorded yet.'),
            ),
          )
        else
          for (final item in items.reversed)
            Card(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.check_rounded)),
                title: Text(
                  '${controller.memberName(item.fromMemberId)} → '
                  '${controller.memberName(item.toMemberId)} · ${_money(item.amountMinor)} '
                  '${controller.trip!.currencyCode}',
                ),
                subtitle: Text(
                  'Recorded by ${controller.memberName(item.confirmedByMemberId)} · '
                  '${_timestamp(item.createdAtMs)}',
                ),
              ),
            ),
      ],
    );
  }
}

String _timestamp(int epochMs) {
  final value = DateTime.fromMillisecondsSinceEpoch(epochMs).toLocal();
  return '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')} '
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}

String _money(int value) {
  final negative = value < 0;
  final digits = value.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
    buffer.write(digits[i]);
  }
  return negative ? '-$buffer' : buffer.toString();
}
