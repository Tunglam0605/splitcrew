import 'package:flutter/material.dart';
import 'package:splitcrew_payment_qr/splitcrew_payment_qr.dart';

import 'app_state.dart';
import 'sync_service.dart';

final class MemberProfilePage extends StatefulWidget {
  const MemberProfilePage({
    super.key,
    required this.controller,
    required this.sync,
    required this.memberId,
  });

  final TripController controller;
  final MobileSyncController sync;
  final String memberId;

  @override
  State<MemberProfilePage> createState() => _MemberProfilePageState();
}

final class _MemberProfilePageState extends State<MemberProfilePage> {
  final _nameController = TextEditingController();
  final _accountController = TextEditingController();
  final _holderController = TextEditingController();
  String? _selectedBankBin;
  bool _initialized = false;
  bool _saving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _loadFromCanonicalSnapshot();
    _initialized = true;
  }

  void _loadFromCanonicalSnapshot() {
    final trip = widget.controller.trip!;
    final member = trip.members.where((item) => item.id == widget.memberId).firstOrNull;
    if (member == null) throw StateError('Member profile no longer exists.');
    final account = widget.controller.paymentAccountForMember(widget.memberId);
    final banks = VietQrPayloadProvider.supportedBanks;
    final currentBin = account?.routingIdentifier;
    _nameController.text = member.name;
    _accountController.text = account?.accountIdentifier ?? '';
    _holderController.text = account?.holderName ?? member.name.toUpperCase();
    _selectedBankBin = currentBin != null && banks.any((bank) => bank.binCode == currentBin)
        ? currentBin
        : banks.first.binCode;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _accountController.dispose();
    _holderController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final trip = widget.controller.trip!;
    final member = trip.members.where((item) => item.id == widget.memberId).firstOrNull;
    if (member == null) {
      _showError('Member profile no longer exists.');
      return;
    }
    final existing = widget.controller.paymentAccountForMember(widget.memberId);
    final cleanName = _nameController.text.trim();
    final cleanAccount = _accountController.text.replaceAll(RegExp(r'\s+'), '');
    final cleanHolder = _holderController.text.trim();
    final bankBin = _selectedBankBin;

    if (cleanName.isEmpty) {
      _showError('Display name is required.');
      return;
    }
    if (existing != null && cleanAccount.isEmpty) {
      _showError('Removing a repayment account from a member device is not enabled yet. Edit it instead.');
      return;
    }
    if (cleanAccount.isNotEmpty && (cleanHolder.isEmpty || bankBin == null)) {
      _showError('Bank, account number and holder name are required together.');
      return;
    }

    final nameChanged = cleanName != member.name;
    final paymentChanged = cleanAccount.isNotEmpty &&
        (existing == null ||
            existing.routingIdentifier != bankBin ||
            existing.accountIdentifier != cleanAccount ||
            existing.holderName != cleanHolder);

    if (!nameChanged && !paymentChanged) {
      if (mounted) Navigator.of(context).pop();
      return;
    }

    setState(() => _saving = true);
    try {
      var queued = false;
      if (nameChanged) {
        final disposition = await widget.sync.renameMember(
          memberId: widget.memberId,
          name: cleanName,
        );
        queued = queued || disposition == SyncWriteDisposition.queued;
      }
      if (paymentChanged) {
        final disposition = await widget.sync.updatePaymentAccount(
          memberId: widget.memberId,
          holderName: cleanHolder,
          bankBin: bankBin!,
          accountIdentifier: cleanAccount,
        );
        queued = queued || disposition == SyncWriteDisposition.queued;
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            queued
                ? 'Profile change queued. The owner device will validate it when the LAN session is available.'
                : 'Profile updated on the owner device.',
          ),
        ),
      );
    } catch (error) {
      _showError(error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final account = widget.controller.paymentAccountForMember(widget.memberId);
    final banks = VietQrPayloadProvider.supportedBanks;
    return Scaffold(
      appBar: AppBar(title: const Text('My crew profile')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Text('Identity', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          TextField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Display name',
              helperText: 'Only your own member profile can be changed from this device.',
            ),
          ),
          const SizedBox(height: 24),
          Text('Repayment account', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            account == null
                ? 'Optional. Add safe routing details so crew members can generate repayment VietQR.'
                : 'Editing this account is version-checked against the owner canonical state.',
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _selectedBankBin,
            decoration: const InputDecoration(labelText: 'Bank'),
            items: [
              for (final bank in banks)
                DropdownMenuItem(
                  value: bank.binCode,
                  child: Text(bank.displayName),
                ),
            ],
            onChanged: _saving ? null : (value) => setState(() => _selectedBankBin = value),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _accountController,
            enabled: !_saving,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Account number'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _holderController,
            enabled: !_saving,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'Account holder name'),
          ),
          const SizedBox(height: 12),
          const Text(
            'Never enter a banking password, PIN, OTP, card CVV, login cookie, or private banking token.',
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_rounded),
            label: Text(_saving ? 'Saving…' : 'Save profile'),
          ),
        ],
      ),
    );
  }
}
