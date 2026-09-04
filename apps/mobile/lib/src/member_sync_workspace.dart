import 'package:flutter/material.dart';
import 'package:splitcrew_domain/splitcrew_domain.dart';
import 'package:splitcrew_split_engine/splitcrew_split_engine.dart';

import 'app_state.dart';
import 'sync_queue_store.dart';
import 'sync_service.dart';
import 'sync_ui.dart';

final class MemberSyncedWorkspace extends StatelessWidget {
  const MemberSyncedWorkspace({
    super.key,
    required this.controller,
    required this.sync,
  });

  final TripController controller;
  final MobileSyncController sync;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([controller, sync]),
      builder: (context, _) {
        final trip = controller.trip!;
        return DefaultTabController(
          length: 4,
          child: Scaffold(
            appBar: AppBar(
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(trip.name),
                  Text(
                    '${sync.memberOnline ? 'Connected' : 'Cached offline'} · rev ${sync.canonicalRevision} · ${sync.pendingCount} pending',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              actions: [
                IconButton(
                  tooltip: 'Crew sync',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => SyncCenterPage(controller: controller, sync: sync),
                    ),
                  ),
                  icon: Icon(
                    sync.blockedCount > 0
                        ? Icons.sync_problem_rounded
                        : sync.memberOnline
                            ? Icons.sync_rounded
                            : Icons.cloud_off_rounded,
                  ),
                ),
              ],
              bottom: const TabBar(
                tabs: [
                  Tab(text: 'Expenses', icon: Icon(Icons.receipt_long_rounded)),
                  Tab(text: 'Balances', icon: Icon(Icons.account_balance_wallet_rounded)),
                  Tab(text: 'Members', icon: Icon(Icons.group_rounded)),
                  Tab(text: 'Queue', icon: Icon(Icons.outbox_rounded)),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                _MemberExpenses(controller: controller, sync: sync),
                _MemberBalances(controller: controller),
                _MemberMembers(controller: controller, sync: sync),
                _MemberQueue(sync: sync),
              ],
            ),
            floatingActionButton: FloatingActionButton.extended(
              onPressed: sync.busy
                  ? null
                  : () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => MemberAddExpensePage(controller: controller, sync: sync),
                        ),
                      ),
              icon: Icon(sync.memberOnline ? Icons.add_rounded : Icons.add_to_queue_rounded),
              label: Text(sync.memberOnline ? 'Synced expense' : 'Queue expense'),
            ),
          ),
        );
      },
    );
  }
}

final class _MemberExpenses extends StatelessWidget {
  const _MemberExpenses({required this.controller, required this.sync});
  final TripController controller;
  final MobileSyncController sync;

  @override
  Widget build(BuildContext context) {
    final expenses = controller.trip!.expenses.reversed.toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        if (sync.pendingCount > 0 || sync.blockedCount > 0) ...[
          Card(
            child: ListTile(
              leading: Icon(sync.blockedCount > 0 ? Icons.warning_amber_rounded : Icons.outbox_rounded),
              title: Text(
                sync.blockedCount > 0
                    ? '${sync.blockedCount} operation(s) need attention'
                    : '${sync.pendingCount} operation(s) waiting for the owner host',
              ),
              subtitle: const Text('Pending writes are not included in canonical balances until the owner commits them.'),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (expenses.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'No canonical expenses yet. You can create an expense now; if the host is offline it will remain visibly queued until committed.',
              textAlign: TextAlign.center,
            ),
          )
        else
          for (final expense in expenses) ...[
            Card(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.receipt_long_rounded)),
                title: Text(expense.title),
                subtitle: Text(
                  'Paid by ${expense.payerMinorByMember.keys.map(controller.memberName).join(', ')} · ${expense.allocationMinorByMember.length} participant(s)',
                ),
                trailing: Text('${_money(expense.totalMinor)} ₫'),
              ),
            ),
            const SizedBox(height: 8),
          ],
      ],
    );
  }
}

final class _MemberBalances extends StatelessWidget {
  const _MemberBalances({required this.controller});
  final TripController controller;

  @override
  Widget build(BuildContext context) {
    final balances = controller.balances;
    final transfers = controller.settlements;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        const Card(
          child: Padding(
            padding: EdgeInsets.all(12),
            child: Text('Balances only use owner-committed canonical expenses. Queued offline writes never change debt calculations early.'),
          ),
        ),
        const SizedBox(height: 12),
        Text('Canonical balances', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        for (final balance in balances)
          Card(
            child: ListTile(
              title: Text(controller.memberName(balance.memberId)),
              trailing: Text(
                '${balance.balance.isPositive ? '+' : ''}${_money(balance.balance.minorUnits)} ₫',
              ),
            ),
          ),
        const SizedBox(height: 18),
        Text('Suggested transfers', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        if (transfers.isEmpty)
          const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('Everyone is settled.')))
        else
          for (final transfer in transfers)
            Card(
              child: ListTile(
                title: Text('${controller.memberName(transfer.fromMemberId)} → ${controller.memberName(transfer.toMemberId)}'),
                trailing: Text('${_money(transfer.amount.minorUnits)} ₫'),
              ),
            ),
      ],
    );
  }
}

final class _MemberMembers extends StatelessWidget {
  const _MemberMembers({required this.controller, required this.sync});
  final TripController controller;
  final MobileSyncController sync;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        for (final member in controller.trip!.members)
          Card(
            child: ListTile(
              leading: CircleAvatar(child: Text(member.name.isEmpty ? '?' : member.name[0].toUpperCase())),
              title: Text(member.name),
              subtitle: Text(
                member.isOwner
                    ? 'Owner · authoritative host'
                    : member.id == sync.memberId
                        ? 'This device profile'
                        : 'Member',
              ),
              trailing: member.id == sync.memberId ? const Icon(Icons.phone_android_rounded) : null,
            ),
          ),
      ],
    );
  }
}

final class _MemberQueue extends StatelessWidget {
  const _MemberQueue({required this.sync});
  final MobileSyncController sync;

  @override
  Widget build(BuildContext context) {
    final entries = sync.pendingEntries;
    if (entries.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('No pending operations. This device matches the owner-committed state.'),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('${sync.pendingCount} queued · ${sync.blockedCount} blocked'),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: sync.flushingQueue || !sync.memberOnline
                      ? null
                      : () async {
                          await sync.flushPendingQueue();
                        },
                  icon: const Icon(Icons.sync_rounded),
                  label: Text(sync.flushingQueue ? 'Syncing…' : 'Retry queued operations'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        for (final entry in entries) ...[
          _PendingOperationCard(sync: sync, entry: entry),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

final class _PendingOperationCard extends StatelessWidget {
  const _PendingOperationCard({required this.sync, required this.entry});
  final MobileSyncController sync;
  final PendingSyncEntry entry;

  @override
  Widget build(BuildContext context) {
    final payload = entry.operation.payload;
    final title = payload['title']?.toString() ?? entry.operation.type.name;
    final total = payload['totalMinor'];
    final blocked = entry.state == PendingSyncState.blocked;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(blocked ? Icons.error_outline_rounded : Icons.schedule_send_rounded),
                const SizedBox(width: 10),
                Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
                if (total is int) Text('${_money(total)} ₫'),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              blocked
                  ? 'Blocked after ${entry.attemptCount} attempt(s)'
                  : 'Queued · ${entry.attemptCount} delivery attempt(s)',
            ),
            Text('Operation ${entry.operation.operationId.substring(0, 8)}…'),
            if (entry.lastError != null) ...[
              const SizedBox(height: 6),
              Text(entry.lastError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                if (blocked)
                  FilledButton.tonal(
                    onPressed: sync.memberOnline
                        ? () async {
                            try {
                              await sync.retryPendingOperation(entry.operation.operationId);
                            } catch (error) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
                              }
                            }
                          }
                        : null,
                    child: const Text('Retry as new operation'),
                  ),
                TextButton(
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (dialogContext) => AlertDialog(
                            title: const Text('Discard pending operation?'),
                            content: const Text('The owner will never receive this local intent after it is discarded.'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
                              FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Discard')),
                            ],
                          ),
                        ) ??
                        false;
                    if (confirmed) await sync.discardPendingOperation(entry.operation.operationId);
                  },
                  child: const Text('Discard'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

final class MemberAddExpensePage extends StatefulWidget {
  const MemberAddExpensePage({
    super.key,
    required this.controller,
    required this.sync,
  });

  final TripController controller;
  final MobileSyncController sync;

  @override
  State<MemberAddExpensePage> createState() => _MemberAddExpensePageState();
}

final class _MemberAddExpensePageState extends State<MemberAddExpensePage> {
  final _titleController = TextEditingController();
  final _totalController = TextEditingController();
  final Set<String> _participants = {};
  late String _payerId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final members = widget.controller.trip!.members;
    _participants.addAll(members.map((member) => member.id));
    _payerId = widget.sync.memberId ?? members.first.id;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _totalController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final totalMinor = _parseMoney(_totalController.text);
    if (_titleController.text.trim().isEmpty || totalMinor == null || totalMinor <= 0) {
      _error('Enter an expense title and a valid amount.');
      return;
    }
    if (_participants.isEmpty) {
      _error('Select at least one participant.');
      return;
    }
    setState(() => _saving = true);
    try {
      final currency = widget.controller.trip!.currencyCode;
      final total = Money(minorUnits: totalMinor, currencyCode: currency);
      final allocations = SplitEngine.equal(total: total, memberIds: _participants);
      final disposition = await widget.sync.createExpense(
        title: _titleController.text,
        totalMinor: totalMinor,
        payers: [ExpensePayer(memberId: _payerId, amount: total)],
        allocations: allocations,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            disposition == SyncWriteDisposition.committed
                ? 'Expense committed by the owner host.'
                : 'Expense saved to the pending queue and will sync automatically.',
          ),
        ),
      );
    } catch (error) {
      if (mounted) _error('$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _error(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final members = widget.controller.trip!.members;
    final online = widget.sync.memberOnline;
    return Scaffold(
      appBar: AppBar(title: Text(online ? 'Add synced expense' : 'Queue offline expense')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                online
                    ? 'This expense is written to a durable operation log before transmission. The owner validates and commits it, then this phone refreshes the canonical snapshot.'
                    : 'The owner host is unavailable. This expense will be stored as a pending intent only; balances will not change until the owner commits it.',
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(labelText: 'Expense title', hintText: 'Dinner, taxi, hotel…'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _totalController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Total (VND)', hintText: '500000'),
          ),
          const SizedBox(height: 18),
          DropdownButtonFormField<String>(
            initialValue: _payerId,
            decoration: const InputDecoration(labelText: 'Who paid?'),
            items: [
              for (final member in members) DropdownMenuItem(value: member.id, child: Text(member.name)),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _payerId = value);
            },
          ),
          const SizedBox(height: 18),
          Text('Split equally between', style: Theme.of(context).textTheme.titleMedium),
          for (final member in members)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(member.name),
              value: _participants.contains(member.id),
              onChanged: (selected) => setState(() {
                if (selected ?? false) {
                  _participants.add(member.id);
                } else {
                  _participants.remove(member.id);
                }
              }),
            ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: Icon(online ? Icons.cloud_upload_outlined : Icons.outbox_rounded),
            label: Text(
              _saving
                  ? 'Saving…'
                  : online
                      ? 'Send to owner'
                      : 'Save to pending queue',
            ),
          ),
          if (!online) ...[
            const SizedBox(height: 10),
            const Text(
              'The same operation ID is retried after reconnect, preventing duplicate expenses when a response is lost.',
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

int? _parseMoney(String input) {
  final normalized = input.replaceAll(RegExp(r'[^0-9]'), '');
  return normalized.isEmpty ? null : int.tryParse(normalized);
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
