import 'dart:io';
import 'dart:typed_data';

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

  Future<StoredReceiptAsset> importBytes({
    required String receiptId,
    required String expenseId,
    required List<int> bytes,
    required String originalName,
    required String mimeType,
    required int createdAtMs,
  });

  Future<Uint8List> readBytes(StoredReceiptAsset receipt);

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
      return _assetFromManagedFile(
        destination: destination,
        receiptId: receiptId,
        expenseId: expenseId,
        originalName: originalName,
        mimeType: mimeType,
        extension: extension,
        createdAtMs: createdAtMs,
      );
    } catch (_) {
      if (await destination.exists()) await destination.delete();
      rethrow;
    }
  }

  @override
  Future<StoredReceiptAsset> importBytes({
    required String receiptId,
    required String expenseId,
    required List<int> bytes,
    required String originalName,
    required String mimeType,
    required int createdAtMs,
  }) async {
    if (bytes.isEmpty) throw ArgumentError('Receipt backup data is empty.');

    final root = await getApplicationSupportDirectory();
    final directory = Directory(p.join(root.path, 'receipts', expenseId));
    await directory.create(recursive: true);
    final extension = _safeExtension('', originalName);
    final storageSuffix = DateTime.now().microsecondsSinceEpoch;
    final destination = File(
      p.join(directory.path, '$receiptId-restore-$storageSuffix$extension'),
    );
    await destination.writeAsBytes(bytes, flush: true);

    try {
      return _assetFromManagedFile(
        destination: destination,
        receiptId: receiptId,
        expenseId: expenseId,
        originalName: originalName,
        mimeType: mimeType,
        extension: extension,
        createdAtMs: createdAtMs,
      );
    } catch (_) {
      if (await destination.exists()) await destination.delete();
      rethrow;
    }
  }

  @override
  Future<Uint8List> readBytes(StoredReceiptAsset receipt) async {
    final file = File(receipt.localPath);
    if (!await file.exists()) {
      throw ArgumentError('Receipt ${receipt.id} is missing from local storage.');
    }
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw ArgumentError('Receipt ${receipt.id} is empty.');
    }
    return bytes;
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

  Future<StoredReceiptAsset> _assetFromManagedFile({
    required File destination,
    required String receiptId,
    required String expenseId,
    required String originalName,
    required String mimeType,
    required String extension,
    required int createdAtMs,
  }) async {
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
  MemoryReceiptFileStore({Map<String, List<int>> initialBytes = const {}})
      : bytesById = {
          for (final entry in initialBytes.entries)
            entry.key: Uint8List.fromList(entry.value),
        };

  final Set<String> deletedIds = <String>{};
  final Map<String, Uint8List> bytesById;

  @override
  Future<StoredReceiptAsset> importFile({
    required String receiptId,
    required String expenseId,
    required String sourcePath,
    required String originalName,
    required String mimeType,
    required int createdAtMs,
  }) async {
    final bytes = Uint8List.fromList(const [1]);
    bytesById[receiptId] = bytes;
    return _memoryAsset(
      receiptId: receiptId,
      expenseId: expenseId,
      localPath: sourcePath,
      bytes: bytes,
      originalName: originalName,
      mimeType: mimeType,
      createdAtMs: createdAtMs,
    );
  }

  @override
  Future<StoredReceiptAsset> importBytes({
    required String receiptId,
    required String expenseId,
    required List<int> bytes,
    required String originalName,
    required String mimeType,
    required int createdAtMs,
  }) async {
    final stored = Uint8List.fromList(bytes);
    bytesById[receiptId] = stored;
    return _memoryAsset(
      receiptId: receiptId,
      expenseId: expenseId,
      localPath: '/memory/$expenseId/$receiptId',
      bytes: stored,
      originalName: originalName,
      mimeType: mimeType,
      createdAtMs: createdAtMs,
    );
  }

  @override
  Future<Uint8List> readBytes(StoredReceiptAsset receipt) async {
    final bytes = bytesById[receipt.id];
    if (bytes == null) throw ArgumentError('Receipt ${receipt.id} is missing.');
    return Uint8List.fromList(bytes);
  }

  @override
  Future<void> deleteFile(StoredReceiptAsset receipt) async {
    deletedIds.add(receipt.id);
    bytesById.remove(receipt.id);
  }

  StoredReceiptAsset _memoryAsset({
    required String receiptId,
    required String expenseId,
    required String localPath,
    required Uint8List bytes,
    required String originalName,
    required String mimeType,
    required int createdAtMs,
  }) {
    return StoredReceiptAsset(
      id: receiptId,
      expenseId: expenseId,
      localPath: localPath,
      sha256: sha256.convert(bytes).toString(),
      originalName: originalName,
      mimeType: mimeType,
      sizeBytes: bytes.length,
      createdAtMs: createdAtMs,
    );
  }
}
