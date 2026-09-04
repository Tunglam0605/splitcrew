import 'package:flutter/material.dart';
import 'package:splitcrew_domain/splitcrew_domain.dart';
import 'package:splitcrew_split_engine/splitcrew_split_engine.dart';

import 'app_state.dart';
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
          length: 3,
          child: Scaffold(
            appBar: AppBar(
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(trip.name),
                  Text(
                    '${sync.memberOnline ? 'Connected' : 'Cached offline'} · revision ${sync.canonicalRevision}',
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
                  icon: Icon(sync.memberOnline ? Icons.sync_rounded : Icons.sync_problem_rounded),
                ),
              ],
              bottom: const TabBar(
                tabs: [
                  Tab(text: 'Expenses', icon: Icon(Icons.receipt_long_rounded)),
                  Tab(text: 'Balances', icon: Icon(Icons.account_balance_wallet_rounded)),
                  Tab(text: 'Members', icon: Icon(Icons.group_rounded)),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                _MemberExpenses(controller: controller),
                _MemberBalances(controller: controller),
                _MemberMembers(controller: controller, sync: sync),
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
              icon: const Icon(Icons.add_rounded),
              label: const Text('Synced expense'),
            ),
          ),
        );
      },
    );
  }
}

final class _MemberExpenses extends StatelessWidget {
  const _MemberExpenses({required this.controller});
  final TripController controller;

  @override
  Widget build(BuildContext context) {
    final expenses = controller.trip!.expenses.reversed.toList();
    if (expenses.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('No expenses yet. Add the first synced expense from this member phone.'),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      itemCount: expenses.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final expense = expenses[index];
        return Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.receipt_long_rounded)),
            title: Text(expense.title),
            subtitle: Text(
              'Paid by ${expense.payerMinorByMember.keys.map(controller.memberName).join(', ')} · ${expense.allocationMinorByMember.length} participant(s)',
            ),
            trailing: Text('${_money(expense.totalMinor)} ₫'),
          ),
        );
      },
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
      await widget.sync.createExpense(
        title: _titleController.text,
        totalMinor: totalMinor,
        payers: [ExpensePayer(memberId: _payerId, amount: total)],
        allocations: allocations,
      );
      if (mounted) Navigator.of(context).pop();
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
    return Scaffold(
      appBar: AppBar(title: const Text('Add synced expense')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        children: [
          const Card(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'This validation flow sends the expense to the owner phone first. The owner validates and commits it before this phone refreshes the canonical snapshot.',
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
            onPressed: _saving || !widget.sync.memberOnline ? null : _save,
            icon: const Icon(Icons.cloud_upload_outlined),
            label: Text(_saving ? 'Sending to owner…' : 'Send and save'),
          ),
          if (!widget.sync.memberOnline) ...[
            const SizedBox(height: 10),
            const Text(
              'Host is unavailable. Offline pending-operation queue is the next sync hardening slice; this build does not silently save an unsent financial operation.',
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
