import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'backup_codec.dart';
import 'backup_service.dart';
import 'sync_service.dart';

final class BackupRecoveryPage extends StatefulWidget {
  const BackupRecoveryPage({
    super.key,
    required this.controller,
    required this.sync,
  });

  final TripController controller;
  final MobileSyncController sync;

  @override
  State<BackupRecoveryPage> createState() => _BackupRecoveryPageState();
}

final class _BackupRecoveryPageState extends State<BackupRecoveryPage> {
  late final TripBackupService _service;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _service = TripBackupService(controller: widget.controller);
  }

  Future<void> _exportBackup() async {
    if (_busy) return;
    final trip = widget.controller.trip;
    if (trip == null) {
      _error('There is no trip to back up.');
      return;
    }
    if (widget.sync.isMemberSession) {
      _error('Only the owner/local device can create a recovery backup.');
      return;
    }
    if (widget.sync.isHostRunning) {
      _error('Stop the Owner Host Session before creating a recovery backup.');
      return;
    }

    final passphrase = await _newPassphrase();
    if (passphrase == null) return;

    setState(() => _busy = true);
    try {
      final bytes = await _service.exportEncrypted(passphrase);
      final path = await FilePicker.saveFile(
        dialogTitle: 'Save encrypted SplitCrew backup',
        fileName: _backupFileName(trip.name),
        type: FileType.custom,
        allowedExtensions: const ['splitcrew'],
        bytes: bytes,
      );
      if (!mounted || path == null) return;
      _message('Encrypted backup saved successfully.');
    } catch (error) {
      if (mounted) _error('$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreBackup() async {
    if (_busy) return;
    if (widget.sync.isMemberSession) {
      _error('Leave the member session before restoring a backup.');
      return;
    }
    if (widget.sync.isHostRunning) {
      _error('Stop the Owner Host Session before restoring a backup.');
      return;
    }

    final picked = await FilePicker.pickFiles(
      dialogTitle: 'Choose a SplitCrew backup',
      type: FileType.custom,
      allowedExtensions: const ['splitcrew'],
      allowMultiple: false,
      withData: false,
    );
    if (picked == null) return;
    final file = picked.files.single;
    if (file.size <= 0 || file.size > TripBackupCodec.maxBackupBytes) {
      _error('Backup file size is invalid or exceeds the safe restore limit.');
      return;
    }
    final path = file.path;
    if (path == null || path.isEmpty) {
      _error('The selected backup cannot be read on this device.');
      return;
    }

    final passphrase = await _existingPassphrase();
    if (passphrase == null) return;

    setState(() => _busy = true);
    try {
      final bytes = await File(path).readAsBytes();
      final decoded = await _service.decodeEncrypted(
        bytes: bytes,
        passphrase: passphrase,
      );
      if (!mounted) return;

      final confirmed = await _confirmRestore(decoded);
      if (!confirmed) return;

      final oldTripId = widget.controller.trip?.id;
      final restored = await _service.restoreDecoded(decoded);
      if (oldTripId != null) {
        await widget.sync.clearPendingOperationsForTrip(oldTripId);
      }
      if (restored.id != oldTripId) {
        await widget.sync.clearPendingOperationsForTrip(restored.id);
      }

      if (!mounted) return;
      _message('Backup restored. The restored trip is now the local canonical state.');
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted) _error('$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _newPassphrase() async {
    final first = TextEditingController();
    final second = TextEditingController();
    String? error;

    final value = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Protect this backup'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'The backup contains trip data, payment routing details and receipt images. '
                'It is encrypted with a passphrase that SplitCrew cannot recover.',
              ),
              const SizedBox(height: 14),
              TextField(
                controller: first,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Passphrase'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: second,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: 'Confirm passphrase',
                  errorText: error,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (first.text.length < 8) {
                  setDialogState(() => error = 'Use at least 8 characters.');
                  return;
                }
                if (first.text != second.text) {
                  setDialogState(() => error = 'Passphrases do not match.');
                  return;
                }
                Navigator.pop(dialogContext, first.text);
              },
              child: const Text('Encrypt backup'),
            ),
          ],
        ),
      ),
    );

    first.dispose();
    second.dispose();
    return value;
  }

  Future<String?> _existingPassphrase() async {
    final controller = TextEditingController();
    String? error;

    final value = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Unlock backup'),
          content: TextField(
            controller: controller,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Backup passphrase',
              errorText: error,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (controller.text.length < 8) {
                  setDialogState(() => error = 'Passphrase must contain at least 8 characters.');
                  return;
                }
                Navigator.pop(dialogContext, controller.text);
              },
              child: const Text('Unlock'),
            ),
          ],
        ),
      ),
    );

    controller.dispose();
    return value;
  }

  Future<bool> _confirmRestore(DecodedTripBackup backup) async {
    final receiptCount = backup.trip.expenses.fold<int>(
      0,
      (sum, expense) => sum + expense.receipts.length,
    );
    final created = backup.createdAtEpochMs <= 0
        ? 'Unknown'
        : DateTime.fromMillisecondsSinceEpoch(backup.createdAtEpochMs).toLocal().toString();

    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Replace local trip with this backup?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Trip: ${backup.trip.name}'),
                Text('Members: ${backup.trip.members.length}'),
                Text('Expenses: ${backup.trip.expenses.length}'),
                Text('Receipts: $receiptCount'),
                Text('Backup created: $created'),
                const SizedBox(height: 12),
                const Text(
                  'The current local trip will be replaced atomically. '
                  'Create a backup of the current trip first if you may need it later.',
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Restore backup'),
              ),
            ],
          ),
        ) ??
        false;
  }

  String _backupFileName(String tripName) {
    final safe = tripName
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '-')
        .replaceAll(RegExp(r'-+'), '-');
    final now = DateTime.now();
    final stamp =
        '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}-'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}';
    return 'splitcrew-${safe.isEmpty ? 'trip' : safe}-$stamp.splitcrew';
  }

  void _error(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _message(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final restoreBlocked = widget.sync.isMemberSession || widget.sync.isHostRunning;
    return Scaffold(
      appBar: AppBar(title: const Text('Backup & recovery')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Encrypted trip backup', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  const Text(
                    'SplitCrew packages the canonical trip, payment routing profiles and local '
                    'receipt evidence, compresses it, derives a 256-bit key with Argon2id and '
                    'encrypts the payload with AES-GCM.',
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: _busy || widget.sync.isMemberSession || widget.sync.isHostRunning
                        ? null
                        : _exportBackup,
                    icon: const Icon(Icons.lock_outline_rounded),
                    label: Text(_busy ? 'Working…' : 'Create encrypted backup'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Owner recovery', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(
                    restoreBlocked
                        ? 'Restore is disabled while this phone is a member client or while Owner Host Session is running.'
                        : 'Restore validates encryption, archive structure, receipt SHA-256 hashes and financial invariants before replacing the local canonical trip.',
                  ),
                  const SizedBox(height: 14),
                  FilledButton.tonalIcon(
                    onPressed: _busy || restoreBlocked ? null : _restoreBackup,
                    icon: const Icon(Icons.restore_rounded),
                    label: const Text('Restore encrypted backup'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Important: SplitCrew does not know your backup passphrase and cannot recover it. '
                'Keep the .splitcrew file and its passphrase in separate safe locations.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
