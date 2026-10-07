import 'package:flutter/material.dart';

import 'app_state.dart';
import 'image_export.dart';

final class TripSummaryPage extends StatefulWidget {
  const TripSummaryPage({
    super.key,
    required this.controller,
    this.isCanonicalReplica = false,
  });

  final TripController controller;
  final bool isCanonicalReplica;

  @override
  State<TripSummaryPage> createState() => _TripSummaryPageState();
}

final class _TripSummaryPageState extends State<TripSummaryPage> {
  final GlobalKey _captureKey = GlobalKey();
  final PngExportService _exporter = const PngExportService();
  bool _exporting = false;

  Future<void> _exportPng() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final bytes = await _exporter.captureBoundary(_captureKey);
      final tripName = widget.controller.trip?.name ?? 'trip';
      final saved = await _exporter.savePng(
        bytes: bytes,
        fileName: _fileName(tripName),
        dialogTitle: 'Save SplitCrew trip summary',
      );
      if (!mounted || !saved) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Trip summary PNG saved.')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$error')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _sharePng() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final bytes = await _exporter.captureBoundary(_captureKey);
      final tripName = widget.controller.trip?.name ?? 'Trip';
      await _exporter.sharePng(
        bytes: bytes,
        fileName: _fileName(tripName),
        subject: 'SplitCrew trip summary',
        text: 'SplitCrew summary for $tripName',
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$error')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  String _fileName(String tripName) {
    final safe = tripName
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '-')
        .replaceAll(RegExp(r'-+'), '-');
    final now = DateTime.now();
    final date =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    return 'splitcrew-${safe.isEmpty ? 'trip' : safe}-$date.png';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trip summary'),
        actions: [
          IconButton(
            tooltip: 'Share summary',
            onPressed: _exporting ? null : _sharePng,
            icon: const Icon(Icons.share_rounded),
          ),
          IconButton(
            tooltip: 'Save PNG',
            onPressed: _exporting ? null : _exportPng,
            icon: _exporting
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_rounded),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Center(
          child: RepaintBoundary(
            key: _captureKey,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: _SummaryCard(
                controller: widget.controller,
                isCanonicalReplica: widget.isCanonicalReplica,
                generatedAt: DateTime.now(),
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _exporting ? null : _exportPng,
        icon: const Icon(Icons.image_outlined),
        label: Text(_exporting ? 'Exporting…' : 'Save PNG'),
      ),
    );
  }
}

final class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.controller,
    required this.isCanonicalReplica,
    required this.generatedAt,
  });

  final TripController controller;
  final bool isCanonicalReplica;
  final DateTime generatedAt;

  @override
  Widget build(BuildContext context) {
    final trip = controller.trip!;
    final balances = controller.balances;
    final settlements = controller.settlements;
    final receiptCount = trip.expenses.fold<int>(
      0,
      (sum, expense) => sum + expense.receipts.length,
    );
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surface,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: scheme.primaryContainer,
                  foregroundColor: scheme.onPrimaryContainer,
                  child: const Icon(Icons.groups_rounded),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        trip.name,
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isCanonicalReplica
                            ? 'Owner-committed canonical snapshot'
                            : 'SplitCrew canonical trip summary',
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _Metric(
                  label: 'Total spent',
                  value: '${_money(controller.totalSpentMinor)} ${trip.currencyCode}',
                ),
                _Metric(label: 'Members', value: '${trip.members.length}'),
                _Metric(label: 'Expenses', value: '${trip.expenses.length}'),
                _Metric(label: 'Receipts', value: '$receiptCount'),
              ],
            ),
            const SizedBox(height: 26),
            Text(
              'Balances',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text('Net = paid − allocated share. Positive means this person should receive money.'),
            const SizedBox(height: 10),
            for (final balance in balances) ...[
              _BalanceRow(
                name: controller.memberName(balance.memberId),
                paidMinor: _paidBy(trip, balance.memberId),
                shareMinor: _allocatedTo(trip, balance.memberId),
                netMinor: balance.balance.minorUnits,
                currencyCode: trip.currencyCode,
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 18),
            Text(
              'Suggested settlement',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            if (settlements.isEmpty)
              _InfoBox(
                icon: Icons.check_circle_outline_rounded,
                text: 'Everyone is settled.',
              )
            else
              for (final transfer in settlements) ...[
                _TransferRow(
                  from: controller.memberName(transfer.fromMemberId),
                  to: controller.memberName(transfer.toMemberId),
                  amountMinor: transfer.amount.minorUnits,
                  currencyCode: trip.currencyCode,
                ),
                const SizedBox(height: 8),
              ],
            const SizedBox(height: 22),
            Divider(color: scheme.outlineVariant),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.verified_outlined, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Generated by SplitCrew · revision ${trip.version} · '
                    '${_timestamp(generatedAt)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

final class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 142),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 3),
          Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

final class _BalanceRow extends StatelessWidget {
  const _BalanceRow({
    required this.name,
    required this.paidMinor,
    required this.shareMinor,
    required this.netMinor,
    required this.currencyCode,
  });

  final String name;
  final int paidMinor;
  final int shareMinor;
  final int netMinor;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          CircleAvatar(
            child: Text(name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase()),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(
                  'Paid ${_money(paidMinor)} · Share ${_money(shareMinor)} $currencyCode',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${netMinor > 0 ? '+' : ''}${_money(netMinor)}',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: netMinor == 0
                      ? scheme.onSurfaceVariant
                      : netMinor > 0
                          ? scheme.primary
                          : scheme.error,
                ),
          ),
        ],
      ),
    );
  }
}

final class _TransferRow extends StatelessWidget {
  const _TransferRow({
    required this.from,
    required this.to,
    required this.amountMinor,
    required this.currencyCode,
  });

  final String from;
  final String to;
  final int amountMinor;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Theme.of(context).colorScheme.secondaryContainer,
      ),
      child: Row(
        children: [
          const Icon(Icons.arrow_forward_rounded),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '$from → $to',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Text(
            '${_money(amountMinor)} $currencyCode',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

final class _InfoBox extends StatelessWidget {
  const _InfoBox({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Theme.of(context).colorScheme.secondaryContainer,
      ),
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

int _paidBy(StoredTrip trip, String memberId) => trip.expenses.fold<int>(
      0,
      (sum, expense) => sum + (expense.payerMinorByMember[memberId] ?? 0),
    );

int _allocatedTo(StoredTrip trip, String memberId) => trip.expenses.fold<int>(
      0,
      (sum, expense) => sum + (expense.allocationMinorByMember[memberId] ?? 0),
    );

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

String _timestamp(DateTime value) {
  final local = value.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')} '
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}
