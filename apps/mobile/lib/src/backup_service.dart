import 'dart:typed_data';

import 'app_state.dart';
import 'backup_codec.dart';
import 'receipt_store.dart';

final class TripBackupService {
  TripBackupService({
    required this.controller,
    ReceiptFileStore? receiptFileStore,
    TripBackupCodec? codec,
  })  : receiptFileStore = receiptFileStore ?? LocalReceiptFileStore(),
        codec = codec ?? TripBackupCodec();

  final TripController controller;
  final ReceiptFileStore receiptFileStore;
  final TripBackupCodec codec;

  Future<Uint8List> exportEncrypted(String passphrase) async {
    final trip = controller.trip;
    if (trip == null) throw StateError('There is no trip to back up.');

    final receiptBytes = <String, Uint8List>{};
    for (final expense in trip.expenses) {
      for (final receipt in expense.receipts) {
        receiptBytes[receipt.id] = await receiptFileStore.readBytes(receipt);
      }
    }

    return codec.encode(
      trip: trip,
      receiptBytesById: receiptBytes,
      passphrase: passphrase,
    );
  }

  Future<DecodedTripBackup> decodeEncrypted({
    required List<int> bytes,
    required String passphrase,
  }) =>
      codec.decode(bytes: bytes, passphrase: passphrase);

  Future<StoredTrip> restoreDecoded(DecodedTripBackup backup) async {
    final previous = controller.trip;
    final imported = <StoredReceiptAsset>[];

    try {
      final restoredExpenses = <StoredExpense>[];
      for (final expense in backup.trip.expenses) {
        final restoredReceipts = <StoredReceiptAsset>[];
        for (final receipt in expense.receipts) {
          final bytes = backup.receiptBytesById[receipt.id];
          if (bytes == null) {
            throw BackupFormatException(
              'Receipt ${receipt.id} is missing from decoded backup data.',
            );
          }

          final managed = await receiptFileStore.importBytes(
            receiptId: receipt.id,
            expenseId: expense.id,
            bytes: bytes,
            originalName: receipt.originalName,
            mimeType: receipt.mimeType,
            createdAtMs: receipt.createdAtMs,
          );
          if (managed.sha256 != receipt.sha256 || managed.sizeBytes != receipt.sizeBytes) {
            await receiptFileStore.deleteFile(managed);
            throw BackupFormatException(
              'Receipt ${receipt.id} changed while being restored.',
            );
          }

          final normalized = StoredReceiptAsset(
            id: receipt.id,
            expenseId: expense.id,
            localPath: managed.localPath,
            sha256: receipt.sha256,
            originalName: receipt.originalName,
            mimeType: receipt.mimeType,
            sizeBytes: receipt.sizeBytes,
            createdAtMs: receipt.createdAtMs,
            version: receipt.version,
          );
          imported.add(normalized);
          restoredReceipts.add(normalized);
        }
        restoredExpenses.add(
          expense.copyWith(receipts: restoredReceipts),
        );
      }

      final restored = backup.trip.copyWith(expenses: restoredExpenses);
      await controller.replaceFromBackup(restored);

      final importedPaths = imported.map((receipt) => receipt.localPath).toSet();
      for (final oldExpense in previous?.expenses ?? const <StoredExpense>[]) {
        for (final oldReceipt in oldExpense.receipts) {
          if (importedPaths.contains(oldReceipt.localPath)) continue;
          try {
            await receiptFileStore.deleteFile(oldReceipt);
          } catch (_) {
            // Database restore is already committed. Orphan cleanup is best-effort
            // and must never roll the user back to an older canonical trip.
          }
        }
      }
      return restored;
    } catch (_) {
      for (final receipt in imported.reversed) {
        try {
          await receiptFileStore.deleteFile(receipt);
        } catch (_) {
          // Preserve the original restore failure.
        }
      }
      rethrow;
    }
  }
}
