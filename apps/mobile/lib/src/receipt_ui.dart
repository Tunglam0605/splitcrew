import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'app_state.dart';

final class ReceiptCenterPage extends StatelessWidget {
  const ReceiptCenterPage({super.key, required this.controller});

  final TripController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final expenses = controller.trip!.expenses.reversed.toList();
        return Scaffold(
          appBar: AppBar(title: const Text('Receipts')),
          body: expenses.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Add an expense first, then attach one or more receipt images as evidence.'),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  itemCount: expenses.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final expense = expenses[index];
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          child: expense.receipts.isEmpty
                              ? const Icon(Icons.receipt_long_outlined)
                              : Text('${expense.receipts.length}'),
                        ),
                        title: Text(expense.title),
                        subtitle: Text(
                          expense.receipts.isEmpty
                              ? 'No receipt attached'
                              : '${expense.receipts.length} receipt image(s) stored locally',
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => ExpenseReceiptsPage(
                              controller: controller,
                              expenseId: expense.id,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}

final class ExpenseReceiptsPage extends StatefulWidget {
  const ExpenseReceiptsPage({
    super.key,
    required this.controller,
    required this.expenseId,
  });

  final TripController controller;
  final String expenseId;

  @override
  State<ExpenseReceiptsPage> createState() => _ExpenseReceiptsPageState();
}

final class _ExpenseReceiptsPageState extends State<ExpenseReceiptsPage> {
  final ImagePicker _picker = ImagePicker();
  bool _importing = false;

  Future<void> _pick(ImageSource source) async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 88,
        maxWidth: 2400,
        maxHeight: 2400,
      );
      if (picked == null) return;
      await widget.controller.addReceiptFromPath(
        expenseId: widget.expenseId,
        sourcePath: picked.path,
        originalName: picked.name,
        mimeType: _mimeFromName(picked.name),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to add receipt: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _remove(StoredReceiptAsset receipt) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Remove receipt?'),
            content: const Text('The local receipt image and its metadata will be deleted from this expense.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Remove'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    try {
      await widget.controller.removeReceipt(
        expenseId: widget.expenseId,
        receiptId: receipt.id,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to remove receipt: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final expense = widget.controller.expenseById(widget.expenseId);
        if (expense == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Receipts')),
            body: const Center(child: Text('Expense no longer exists.')),
          );
        }
        return Scaffold(
          appBar: AppBar(title: Text('${expense.title} · receipts')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(14),
                  child: Text(
                    'Receipt images are copied into SplitCrew-managed local storage. They are not uploaded anywhere unless you explicitly export or share them later.',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: _importing ? null : () => _pick(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera_rounded),
                    label: Text(_importing ? 'Importing…' : 'Take photo'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _importing ? null : () => _pick(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Choose image'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'Receipt evidence (${expense.receipts.length}/8)',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              if (expense.receipts.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(18),
                    child: Text('No receipt images attached yet.'),
                  ),
                )
              else
                for (final receipt in expense.receipts) ...[
                  _ReceiptCard(receipt: receipt, onRemove: () => _remove(receipt)),
                  const SizedBox(height: 10),
                ],
            ],
          ),
        );
      },
    );
  }
}

final class _ReceiptCard extends StatelessWidget {
  const _ReceiptCard({required this.receipt, required this.onRemove});

  final StoredReceiptAsset receipt;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final file = File(receipt.localPath);
    final exists = file.existsSync();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: exists
                ? () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => _ReceiptPreviewPage(receipt: receipt),
                      ),
                    )
                : null,
            child: SizedBox(
              height: 220,
              child: exists
                  ? Image.file(file, fit: BoxFit.cover, errorBuilder: (_, _, _) => const _MissingReceipt())
                  : const _MissingReceipt(),
            ),
          ),
          ListTile(
            title: Text(receipt.originalName, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              '${_formatBytes(receipt.sizeBytes)} · SHA-256 ${receipt.sha256.substring(0, 12)}…',
            ),
            trailing: IconButton(
              tooltip: 'Remove receipt',
              onPressed: onRemove,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ),
        ],
      ),
    );
  }
}

final class _ReceiptPreviewPage extends StatelessWidget {
  const _ReceiptPreviewPage({required this.receipt});

  final StoredReceiptAsset receipt;

  @override
  Widget build(BuildContext context) {
    final file = File(receipt.localPath);
    return Scaffold(
      appBar: AppBar(title: Text(receipt.originalName)),
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: InteractiveViewer(
            minScale: 0.7,
            maxScale: 5,
            child: Image.file(
              file,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const _MissingReceipt(),
            ),
          ),
        ),
      ),
    );
  }
}

final class _MissingReceipt extends StatelessWidget {
  const _MissingReceipt();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image_outlined, size: 48),
          SizedBox(height: 8),
          Text('Receipt file is missing'),
        ],
      ),
    );
  }
}

String _mimeFromName(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.heic')) return 'image/heic';
  if (lower.endsWith('.heif')) return 'image/heif';
  return 'image/jpeg';
}

String _formatBytes(int value) {
  if (value < 1024) return '$value B';
  if (value < 1024 * 1024) return '${(value / 1024).toStringAsFixed(1)} KB';
  return '${(value / (1024 * 1024)).toStringAsFixed(1)} MB';
}
