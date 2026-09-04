import 'package:flutter/material.dart';
import 'package:splitcrew_domain/splitcrew_domain.dart';
import 'package:splitcrew_split_engine/splitcrew_split_engine.dart';

import 'app_state.dart';

enum ExpenseSplitMode { equal, exact, percentage, shares }

final class CreateTripPage extends StatefulWidget {
  const CreateTripPage({super.key, required this.controller, this.loadError});

  final TripController controller;
  final String? loadError;

  @override
  State<CreateTripPage> createState() => _CreateTripPageState();
}

final class _CreateTripPageState extends State<CreateTripPage> {
  final _tripController = TextEditingController();
  final _ownerController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _tripController.dispose();
    _ownerController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() => _saving = true);
    try {
      await widget.controller.createTrip(
        name: _tripController.text,
        ownerName: _ownerController.text,
      );
    } catch (error) {
      if (mounted) _showError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.groups_rounded, size: 72),
                  const SizedBox(height: 20),
                  Text('SplitCrew', style: Theme.of(context).textTheme.headlineLarge, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  const Text(
                    'Shared expenses without a cloud account. Your crew data stays on this phone and works offline.',
                    textAlign: TextAlign.center,
                  ),
                  if (widget.loadError != null) ...[
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(widget.loadError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  TextField(
                    controller: _tripController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Trip / crew name', hintText: 'Da Nang 2026'),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _ownerController,
                    onSubmitted: (_) => _saving ? null : _create(),
                    decoration: const InputDecoration(labelText: 'Your name', hintText: 'Lam'),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _saving ? null : _create,
                    icon: const Icon(Icons.arrow_forward_rounded),
                    label: Text(_saving ? 'Creating…' : 'Create crew'),
                  ),
                  const SizedBox(height: 16),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.offline_bolt_outlined, size: 18),
                      SizedBox(width: 6),
                      Text('Local-first · no server required'),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class TripDashboard extends StatelessWidget {
  const TripDashboard({super.key, required this.controller});

  final TripController controller;

  @override
  Widget build(BuildContext context) {
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
                '${trip.members.length} members · ${_money(controller.totalSpentMinor)} ${trip.currencyCode}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Add member',
              onPressed: () => _showAddMemberDialog(context, controller),
              icon: const Icon(Icons.person_add_alt_1_rounded),
            ),
            PopupMenuButton<String>(
              onSelected: (value) async {
                if (value == 'rename') {
                  await _showRenameTripDialog(context, controller);
                } else if (value == 'reset') {
                  final confirmed = await _confirm(
                    context,
                    title: 'Delete local crew?',
                    message: 'This permanently deletes this crew and all expenses stored on this phone.',
                    confirmLabel: 'Delete',
                  );
                  if (confirmed) await controller.reset();
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rename', child: Text('Rename crew')),
                PopupMenuItem(value: 'reset', child: Text('Delete local crew')),
              ],
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
            _ExpensesTab(controller: controller),
            _BalancesTab(controller: controller),
            _MembersTab(controller: controller),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => AddExpensePage(controller: controller)),
          ),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Expense'),
        ),
      ),
    );
  }
}

final class _ExpensesTab extends StatelessWidget {
  const _ExpensesTab({required this.controller});

  final TripController controller;

  @override
  Widget build(BuildContext context) {
    final trip = controller.trip!;
    final expenses = trip.expenses.reversed.toList();
    if (expenses.isEmpty) {
      return const _EmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'No expenses yet',
        message: 'Add the first bill. You can split equally, by exact amount, percentage, or shares.',
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                label: 'Total spent',
                value: '${_money(controller.totalSpentMinor)} ₫',
                icon: Icons.payments_outlined,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MetricCard(
                label: 'Expenses',
                value: '${expenses.length}',
                icon: Icons.receipt_outlined,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        for (final expense in expenses) ...[
          Card(
            child: ListTile(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ExpenseDetailPage(controller: controller, expenseId: expense.id),
                ),
              ),
              leading: const CircleAvatar(child: Icon(Icons.receipt_long_rounded)),
              title: Text(expense.title),
              subtitle: Text(
                'Paid by ${_payerSummary(controller, expense)}\n${expense.allocationMinorByMember.length} participant(s)',
              ),
              isThreeLine: true,
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${_money(expense.totalMinor)} ₫', style: Theme.of(context).textTheme.titleMedium),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

final class _BalancesTab extends StatelessWidget {
  const _BalancesTab({required this.controller});

  final TripController controller;

  @override
  Widget build(BuildContext context) {
    final balances = controller.balances;
    final transfers = controller.settlements;
    final trip = controller.trip!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        Text('Net balances', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        const Text('Net = money paid − your allocated share.'),
        const SizedBox(height: 8),
        for (final balance in balances)
          Card(
            child: ListTile(
              title: Text(controller.memberName(balance.memberId)),
              subtitle: Text(
                'Paid ${_money(_paidBy(trip, balance.memberId))} · Share ${_money(_allocatedTo(trip, balance.memberId))}',
              ),
              trailing: Text(
                '${balance.balance.isPositive ? '+' : ''}${_money(balance.balance.minorUnits)} ₫',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: balance.balance.isPositive
                          ? Theme.of(context).colorScheme.primary
                          : balance.balance.isNegative
                              ? Theme.of(context).colorScheme.error
                              : null,
                    ),
              ),
            ),
          ),
        const SizedBox(height: 20),
        Text('Suggested transfers', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        const Text('A deterministic settlement that clears the current balances.'),
        const SizedBox(height: 8),
        if (transfers.isEmpty)
          const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('Everyone is settled.')))
        else
          for (final transfer in transfers)
            Card(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.arrow_forward_rounded)),
                title: Text('${controller.memberName(transfer.fromMemberId)} → ${controller.memberName(transfer.toMemberId)}'),
                subtitle: const Text('Suggested repayment'),
                trailing: Text('${_money(transfer.amount.minorUnits)} ₫'),
              ),
            ),
      ],
    );
  }
}

final class _MembersTab extends StatelessWidget {
  const _MembersTab({required this.controller});

  final TripController controller;

  @override
  Widget build(BuildContext context) {
    final members = controller.trip!.members;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        for (final member in members)
          Card(
            child: ListTile(
              leading: CircleAvatar(child: Text(member.name.isEmpty ? '?' : member.name[0].toUpperCase())),
              title: Text(member.name),
              subtitle: Text(member.isOwner ? 'Owner' : 'Member · local profile'),
              trailing: member.isOwner
                  ? const Icon(Icons.workspace_premium_rounded)
                  : PopupMenuButton<String>(
                      onSelected: (value) async {
                        if (value == 'rename') {
                          await _showRenameMemberDialog(context, controller, member);
                        } else if (value == 'remove') {
                          final confirmed = await _confirm(
                            context,
                            title: 'Remove ${member.name}?',
                            message: 'Members referenced by an expense cannot be removed until those expenses are edited or deleted.',
                            confirmLabel: 'Remove',
                          );
                          if (!confirmed) return;
                          try {
                            await controller.removeMember(member.id);
                          } catch (error) {
                            if (context.mounted) _showError(context, error);
                          }
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'rename', child: Text('Rename')),
                        PopupMenuItem(value: 'remove', child: Text('Remove')),
                      ],
                    ),
            ),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _showAddMemberDialog(context, controller),
          icon: const Icon(Icons.person_add_alt_1_rounded),
          label: const Text('Add member'),
        ),
      ],
    );
  }
}

final class ExpenseDetailPage extends StatelessWidget {
  const ExpenseDetailPage({super.key, required this.controller, required this.expenseId});

  final TripController controller;
  final String expenseId;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final expense = controller.expenseById(expenseId);
        if (expense == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Expense')),
            body: const _EmptyState(
              icon: Icons.delete_outline_rounded,
              title: 'Expense no longer exists',
              message: 'It may have been deleted.',
            ),
          );
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(expense.title),
            actions: [
              IconButton(
                tooltip: 'Edit expense',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AddExpensePage(controller: controller, initialExpense: expense),
                  ),
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) async {
                  if (value != 'delete') return;
                  final confirmed = await _confirm(
                    context,
                    title: 'Delete expense?',
                    message: 'Balances will be recalculated immediately.',
                    confirmLabel: 'Delete',
                  );
                  if (confirmed) {
                    await controller.removeExpense(expense.id);
                    if (context.mounted) Navigator.of(context).pop();
                  }
                },
                itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Delete expense'))],
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Total', style: Theme.of(context).textTheme.labelLarge),
                      const SizedBox(height: 4),
                      Text('${_money(expense.totalMinor)} ₫', style: Theme.of(context).textTheme.headlineMedium),
                      const SizedBox(height: 10),
                      Text('Version ${expense.version} · updated ${_dateTime(expense.updatedAtMs)}'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Paid by', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              for (final entry in expense.payerMinorByMember.entries)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.payments_outlined),
                    title: Text(controller.memberName(entry.key)),
                    trailing: Text('${_money(entry.value)} ₫'),
                  ),
                ),
              const SizedBox(height: 16),
              Text('Allocated share', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              const Text('These final integer amounts are the auditable source used by settlement calculations.'),
              const SizedBox(height: 8),
              for (final entry in expense.allocationMinorByMember.entries)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.pie_chart_outline_rounded),
                    title: Text(controller.memberName(entry.key)),
                    trailing: Text('${_money(entry.value)} ₫'),
                  ),
                ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AddExpensePage(controller: controller, initialExpense: expense),
                  ),
                ),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit expense'),
              ),
            ],
          ),
        );
      },
    );
  }
}

final class AddExpensePage extends StatefulWidget {
  const AddExpensePage({super.key, required this.controller, this.initialExpense});

  final TripController controller;
  final StoredExpense? initialExpense;

  bool get isEditing => initialExpense != null;

  @override
  State<AddExpensePage> createState() => _AddExpensePageState();
}

final class _AddExpensePageState extends State<AddExpensePage> {
  final _titleController = TextEditingController();
  final _totalController = TextEditingController();
  final Map<String, TextEditingController> _payerControllers = {};
  final Map<String, TextEditingController> _splitControllers = {};
  final Set<String> _participants = {};
  ExpenseSplitMode _mode = ExpenseSplitMode.equal;
  bool _multiplePayers = false;
  bool _saving = false;
  late String _singlePayerId;

  List<StoredMember> get _members => widget.controller.trip!.members;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialExpense;
    _singlePayerId = initial?.payerMinorByMember.keys.firstOrNull ?? _members.first.id;
    for (final member in _members) {
      _payerControllers[member.id] = TextEditingController();
      _splitControllers[member.id] = TextEditingController();
    }
    if (initial == null) {
      _participants.addAll(_members.map((member) => member.id));
      return;
    }
    _titleController.text = initial.title;
    _totalController.text = initial.totalMinor.toString();
    _participants.addAll(initial.allocationMinorByMember.keys);
    _multiplePayers = initial.payerMinorByMember.length > 1;
    for (final entry in initial.payerMinorByMember.entries) {
      _payerControllers[entry.key]?.text = entry.value.toString();
    }
    for (final entry in initial.allocationMinorByMember.entries) {
      _splitControllers[entry.key]?.text = entry.value.toString();
    }
    _mode = ExpenseSplitMode.exact;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _totalController.dispose();
    for (final controller in _payerControllers.values) {
      controller.dispose();
    }
    for (final controller in _splitControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final totalMinor = _parseMoneyInput(_totalController.text);
    if (totalMinor == null || totalMinor <= 0) {
      _showError(context, 'Enter a valid total amount greater than zero.');
      return;
    }
    if (_participants.isEmpty) {
      _showError(context, 'Select at least one participant.');
      return;
    }

    setState(() => _saving = true);
    try {
      final currency = widget.controller.trip!.currencyCode;
      final total = Money(minorUnits: totalMinor, currencyCode: currency);
      final payers = <ExpensePayer>[];
      if (_multiplePayers) {
        for (final member in _members) {
          final value = _parseMoneyInput(_payerControllers[member.id]!.text) ?? 0;
          if (value > 0) {
            payers.add(
              ExpensePayer(
                memberId: member.id,
                amount: Money(minorUnits: value, currencyCode: currency),
              ),
            );
          }
        }
      } else {
        payers.add(ExpensePayer(memberId: _singlePayerId, amount: total));
      }

      final allocations = switch (_mode) {
        ExpenseSplitMode.equal => SplitEngine.equal(total: total, memberIds: _participants),
        ExpenseSplitMode.exact => SplitEngine.exact(
            total: total,
            amounts: {
              for (final id in _participants)
                id: Money(
                  minorUnits: _parseMoneyInput(_splitControllers[id]!.text) ?? 0,
                  currencyCode: currency,
                ),
            },
          ),
        ExpenseSplitMode.percentage => SplitEngine.percentages(
            total: total,
            basisPoints: {
              for (final id in _participants) id: _parseBasisPoints(_splitControllers[id]!.text),
            },
          ),
        ExpenseSplitMode.shares => SplitEngine.shares(
            total: total,
            shares: {
              for (final id in _participants) id: int.tryParse(_splitControllers[id]!.text.trim()) ?? 0,
            },
          ),
      };

      if (widget.initialExpense == null) {
        await widget.controller.addExpense(
          title: _titleController.text,
          totalMinor: totalMinor,
          payers: payers,
          allocations: allocations,
        );
      } else {
        await widget.controller.updateExpense(
          expenseId: widget.initialExpense!.id,
          title: _titleController.text,
          totalMinor: totalMinor,
          payers: payers,
          allocations: allocations,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) _showError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.isEditing ? 'Edit expense' : 'Add expense')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        children: [
          if (widget.isEditing) ...[
            const Card(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text('Editing uses the current final allocation as exact amounts. You can switch to another split method before saving.'),
              ),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _titleController,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Expense title', hintText: 'Dinner, taxi, hotel…'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _totalController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Total (VND)', hintText: '1250000'),
          ),
          const SizedBox(height: 20),
          Text('Who paid?', style: Theme.of(context).textTheme.titleMedium),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Multiple payers'),
            subtitle: const Text('Use when several members paid parts of the same bill.'),
            value: _multiplePayers,
            onChanged: (value) => setState(() => _multiplePayers = value),
          ),
          if (!_multiplePayers)
            DropdownButtonFormField<String>(
              initialValue: _singlePayerId,
              decoration: const InputDecoration(labelText: 'Payer'),
              items: [
                for (final member in _members) DropdownMenuItem(value: member.id, child: Text(member.name)),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _singlePayerId = value);
              },
            )
          else
            ...[
              for (final member in _members) ...[
                TextField(
                  controller: _payerControllers[member.id],
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: '${member.name} paid'),
                ),
                const SizedBox(height: 8),
              ],
            ],
          const SizedBox(height: 24),
          Text('Who shares this expense?', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          for (final member in _members)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(member.name),
              value: _participants.contains(member.id),
              onChanged: (selected) {
                setState(() {
                  if (selected ?? false) {
                    _participants.add(member.id);
                  } else {
                    _participants.remove(member.id);
                  }
                });
              },
            ),
          const SizedBox(height: 16),
          DropdownButtonFormField<ExpenseSplitMode>(
            initialValue: _mode,
            decoration: const InputDecoration(labelText: 'Split method'),
            items: const [
              DropdownMenuItem(value: ExpenseSplitMode.equal, child: Text('Equal')),
              DropdownMenuItem(value: ExpenseSplitMode.exact, child: Text('Exact amount per person')),
              DropdownMenuItem(value: ExpenseSplitMode.percentage, child: Text('Percentage')),
              DropdownMenuItem(value: ExpenseSplitMode.shares, child: Text('Shares / weights')),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _mode = value);
            },
          ),
          if (_mode != ExpenseSplitMode.equal) ...[
            const SizedBox(height: 12),
            for (final member in _members.where((member) => _participants.contains(member.id))) ...[
              TextField(
                controller: _splitControllers[member.id],
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: switch (_mode) {
                    ExpenseSplitMode.exact => '${member.name} amount',
                    ExpenseSplitMode.percentage => '${member.name} %',
                    ExpenseSplitMode.shares => '${member.name} shares',
                    ExpenseSplitMode.equal => member.name,
                  },
                  helperText: _mode == ExpenseSplitMode.percentage ? 'Percentages must total 100.00%' : null,
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.check_rounded),
            label: Text(_saving ? 'Saving…' : widget.isEditing ? 'Save changes' : 'Save expense'),
          ),
        ],
      ),
    );
  }
}

final class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon),
            const SizedBox(height: 10),
            Text(value, style: Theme.of(context).textTheme.titleMedium),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

final class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.title, required this.message});

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

Future<void> _showAddMemberDialog(BuildContext context, TripController controller) async {
  final textController = TextEditingController();
  try {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add member'),
        content: TextField(
          controller: textController,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Display name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              try {
                await controller.addMember(textController.text);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              } catch (error) {
                if (dialogContext.mounted) _showError(dialogContext, error);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  } finally {
    textController.dispose();
  }
}

Future<void> _showRenameTripDialog(BuildContext context, TripController controller) async {
  final textController = TextEditingController(text: controller.trip!.name);
  try {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename crew'),
        content: TextField(controller: textController, autofocus: true, decoration: const InputDecoration(labelText: 'Crew name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              try {
                await controller.renameTrip(textController.text);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              } catch (error) {
                if (dialogContext.mounted) _showError(dialogContext, error);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  } finally {
    textController.dispose();
  }
}

Future<void> _showRenameMemberDialog(BuildContext context, TripController controller, StoredMember member) async {
  final textController = TextEditingController(text: member.name);
  try {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename member'),
        content: TextField(controller: textController, autofocus: true, decoration: const InputDecoration(labelText: 'Display name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              try {
                await controller.renameMember(member.id, textController.text);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              } catch (error) {
                if (dialogContext.mounted) _showError(dialogContext, error);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  } finally {
    textController.dispose();
  }
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(confirmLabel)),
          ],
        ),
      ) ??
      false;
}

void _showError(BuildContext context, Object error) {
  final message = error is ArgumentError ? (error.message?.toString() ?? error.toString()) : error.toString();
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

int? _parseMoneyInput(String input) {
  final normalized = input.replaceAll(RegExp(r'[^0-9-]'), '');
  if (normalized.isEmpty || normalized == '-') return null;
  return int.tryParse(normalized);
}

int _parseBasisPoints(String input) {
  final normalized = input.trim().replaceAll(',', '.');
  if (normalized.isEmpty) return 0;
  final parts = normalized.split('.');
  if (parts.length > 2) throw ArgumentError('Invalid percentage: $input');
  final whole = int.tryParse(parts[0]);
  if (whole == null || whole < 0 || whole > 100) {
    throw ArgumentError('Invalid percentage: $input');
  }
  var fraction = parts.length == 2 ? parts[1] : '';
  if (fraction.length > 2 || (fraction.isNotEmpty && int.tryParse(fraction) == null)) {
    throw ArgumentError('Use at most two decimal places for percentages.');
  }
  fraction = fraction.padRight(2, '0');
  final fractional = fraction.isEmpty ? 0 : int.parse(fraction);
  final result = whole * 100 + fractional;
  if (result > 10000) throw ArgumentError('Percentage cannot exceed 100%.');
  return result;
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

String _payerSummary(TripController controller, StoredExpense expense) => expense.payerMinorByMember.entries
    .map((entry) => '${controller.memberName(entry.key)} ${_money(entry.value)}')
    .join(' + ');

int _paidBy(StoredTrip trip, String memberId) => trip.expenses.fold(
      0,
      (sum, expense) => sum + (expense.payerMinorByMember[memberId] ?? 0),
    );

int _allocatedTo(StoredTrip trip, String memberId) => trip.expenses.fold(
      0,
      (sum, expense) => sum + (expense.allocationMinorByMember[memberId] ?? 0),
    );

String _dateTime(int milliseconds) {
  if (milliseconds <= 0) return 'legacy data';
  final value = DateTime.fromMillisecondsSinceEpoch(milliseconds).toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(value.day)}/${two(value.month)}/${value.year} ${two(value.hour)}:${two(value.minute)}';
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
