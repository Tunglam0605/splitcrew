import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'stored_models.dart';

abstract interface class ReceiptFileStore {
  Future<StoredReceiptAsset> importFile({
    required String receiptId,
    required String expenseId,
    required String sourcePath,
    required String originalName,
    required String mimeType,
    required int createdAtMs,
  });

  Future<void> deleteFile(StoredReceiptAsset receipt);
}

final class LocalReceiptFileStore implements ReceiptFileStore {
  @override
  Future<StoredReceiptAsset> importFile({
    required String receiptId,
    required String expenseId,
    required String sourcePath,
    required String originalName,
    required String mimeType,
    required int createdAtMs,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) throw ArgumentError('Selected receipt file no longer exists.');
    final length = await source.length();
    if (length <= 0) throw ArgumentError('Selected receipt file is empty.');

    final root = await getApplicationSupportDirectory();
    final directory = Directory(p.join(root.path, 'receipts', expenseId));
    await directory.create(recursive: true);
    final extension = _safeExtension(sourcePath, originalName);
    final destination = File(p.join(directory.path, '$receiptId$extension'));
    await source.copy(destination.path);

    try {
      final digest = await sha256.bind(destination.openRead()).first;
      return StoredReceiptAsset(
        id: receiptId,
        expenseId: expenseId,
        localPath: destination.path,
        sha256: digest.toString(),
        originalName: originalName.trim().isEmpty ? 'receipt$extension' : originalName.trim(),
        mimeType: mimeType.trim().isEmpty ? _mimeFromExtension(extension) : mimeType.trim(),
        sizeBytes: await destination.length(),
        createdAtMs: createdAtMs,
      );
    } catch (_) {
      if (await destination.exists()) await destination.delete();
      rethrow;
    }
  }

  @override
  Future<void> deleteFile(StoredReceiptAsset receipt) async {
    final file = File(receipt.localPath);
    if (await file.exists()) await file.delete();
    final parent = file.parent;
    if (await parent.exists() && await parent.list().isEmpty) {
      await parent.delete();
    }
  }

  String _safeExtension(String sourcePath, String originalName) {
    final candidate = p.extension(originalName).isNotEmpty ? p.extension(originalName) : p.extension(sourcePath);
    final normalized = candidate.toLowerCase();
    return switch (normalized) {
      '.jpg' || '.jpeg' || '.png' || '.webp' || '.heic' || '.heif' => normalized,
      _ => '.jpg',
    };
  }

  String _mimeFromExtension(String extension) => switch (extension) {
        '.png' => 'image/png',
        '.webp' => 'image/webp',
        '.heic' => 'image/heic',
        '.heif' => 'image/heif',
        _ => 'image/jpeg',
      };
}

final class MemoryReceiptFileStore implements ReceiptFileStore {
  final Set<String> deletedIds = <String>{};

  @override
  Future<StoredReceiptAsset> importFile({
    required String receiptId,
    required String expenseId,
    required String sourcePath,
    required String originalName,
    required String mimeType,
    required int createdAtMs,
  }) async {
    return StoredReceiptAsset(
      id: receiptId,
      expenseId: expenseId,
      localPath: sourcePath,
      sha256: List.filled(64, '0').join(),
      originalName: originalName,
      mimeType: mimeType,
      sizeBytes: 1,
      createdAtMs: createdAtMs,
    );
  }

  @override
  Future<void> deleteFile(StoredReceiptAsset receipt) async {
    deletedIds.add(receipt.id);
  }
}
