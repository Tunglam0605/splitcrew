import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';

import 'stored_models.dart';

final class DecodedTripBackup {
  const DecodedTripBackup({
    required this.trip,
    required this.receiptBytesById,
    required this.createdAtEpochMs,
  });

  final StoredTrip trip;
  final Map<String, Uint8List> receiptBytesById;
  final int createdAtEpochMs;
}

final class BackupFormatException implements Exception {
  const BackupFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class TripBackupCodec {
  TripBackupCodec({
    this.kdfMemoryKiB = 19456,
    this.kdfIterations = 2,
    this.kdfParallelism = 1,
  });

  static const formatName = 'splitcrew-encrypted-backup';
  static const formatVersion = 1;
  static const _tripEntryName = 'trip.json';

  static const maxBackupBytes = 160 * 1024 * 1024;
  static const maxReceiptBytes = 25 * 1024 * 1024;
  static const maxTotalReceiptBytes = 200 * 1024 * 1024;
  static const maxReceiptCount = 512;
  static const maxTripJsonBytes = 5 * 1024 * 1024;

  final int kdfMemoryKiB;
  final int kdfIterations;
  final int kdfParallelism;

  Future<Uint8List> encode({
    required StoredTrip trip,
    required Map<String, Uint8List> receiptBytesById,
    required String passphrase,
  }) async {
    _validatePassphrase(passphrase);
    _validateKdfParameters(
      memoryKiB: kdfMemoryKiB,
      iterations: kdfIterations,
      parallelism: kdfParallelism,
    );

    final archive = Archive();
    final portableTrip = _portableTripJson(trip);
    final tripJson = utf8.encode(jsonEncode(portableTrip));
    if (tripJson.length > maxTripJsonBytes) {
      throw const BackupFormatException('Trip metadata is too large to back up safely.');
    }
    archive.add(ArchiveFile.bytes(_tripEntryName, tripJson));

    var receiptCount = 0;
    var totalReceiptBytes = 0;
    for (final expense in trip.expenses) {
      for (final receipt in expense.receipts) {
        receiptCount++;
        if (receiptCount > maxReceiptCount) {
          throw const BackupFormatException('This trip contains too many receipt files for one backup.');
        }
        final bytes = receiptBytesById[receipt.id];
        if (bytes == null) {
          throw BackupFormatException('Receipt ${receipt.id} is missing from local storage.');
        }
        if (bytes.isEmpty || bytes.length > maxReceiptBytes) {
          throw BackupFormatException('Receipt ${receipt.id} has an invalid backup size.');
        }
        totalReceiptBytes += bytes.length;
        if (totalReceiptBytes > maxTotalReceiptBytes) {
          throw const BackupFormatException('Receipt data is too large for one backup.');
        }
        final digest = sha256.convert(bytes).toString();
        if (digest != receipt.sha256) {
          throw BackupFormatException('Receipt ${receipt.id} failed its SHA-256 integrity check.');
        }
        archive.add(
          ArchiveFile.bytes(
            _receiptArchivePath(expense.id, receipt.id),
            bytes,
          ),
        );
      }
    }

    final zipped = ZipEncoder().encode(archive);
    if (zipped.length > maxBackupBytes) {
      throw const BackupFormatException('Compressed backup is too large.');
    }

    final salt = Uint8List.fromList(
      List<int>.generate(16, (_) => Random.secure().nextInt(256)),
    );
    final kdf = Argon2id(
      memory: kdfMemoryKiB,
      parallelism: kdfParallelism,
      iterations: kdfIterations,
      hashLength: 32,
    );
    final secretKey = await kdf.deriveKeyFromPassword(
      password: passphrase,
      nonce: salt,
    );
    final cipher = AesGcm.with256bits();
    final secretBox = await cipher.encrypt(
      zipped,
      secretKey: secretKey,
    );

    final envelope = <String, Object?>{
      'format': formatName,
      'formatVersion': formatVersion,
      'createdAtEpochMs': DateTime.now().millisecondsSinceEpoch,
      'kdf': {
        'name': 'argon2id',
        'memoryKiB': kdfMemoryKiB,
        'iterations': kdfIterations,
        'parallelism': kdfParallelism,
        'hashLength': 32,
        'salt': base64Encode(salt),
      },
      'cipher': {
        'name': 'aes-gcm-256',
        'payload': base64Encode(secretBox.concatenation()),
      },
    };
    final encoded = Uint8List.fromList(utf8.encode(jsonEncode(envelope)));
    if (encoded.length > maxBackupBytes) {
      throw const BackupFormatException('Encrypted backup is too large.');
    }
    return encoded;
  }

  Future<DecodedTripBackup> decode({
    required List<int> bytes,
    required String passphrase,
  }) async {
    _validatePassphrase(passphrase);
    if (bytes.isEmpty || bytes.length > maxBackupBytes) {
      throw const BackupFormatException('Backup file size is invalid.');
    }

    final Map<String, dynamic> envelope;
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) throw const FormatException('Expected an object.');
      envelope = Map<String, dynamic>.from(decoded);
    } catch (_) {
      throw const BackupFormatException('This is not a valid SplitCrew backup file.');
    }

    if (envelope['format'] != formatName || envelope['formatVersion'] != formatVersion) {
      throw const BackupFormatException('Unsupported SplitCrew backup format.');
    }
    final createdAtEpochMs = envelope['createdAtEpochMs'] as int? ?? 0;

    final kdfJson = _map(envelope['kdf'], 'KDF metadata');
    if (kdfJson['name'] != 'argon2id' || kdfJson['hashLength'] != 32) {
      throw const BackupFormatException('Unsupported backup key-derivation settings.');
    }
    final memoryKiB = kdfJson['memoryKiB'] as int?;
    final iterations = kdfJson['iterations'] as int?;
    final parallelism = kdfJson['parallelism'] as int?;
    if (memoryKiB == null || iterations == null || parallelism == null) {
      throw const BackupFormatException('Backup KDF parameters are incomplete.');
    }
    _validateKdfParameters(
      memoryKiB: memoryKiB,
      iterations: iterations,
      parallelism: parallelism,
    );

    final List<int> salt;
    final List<int> concatenated;
    try {
      salt = base64Decode(kdfJson['salt'] as String);
      final cipherJson = _map(envelope['cipher'], 'cipher metadata');
      if (cipherJson['name'] != 'aes-gcm-256') {
        throw const BackupFormatException('Unsupported backup cipher.');
      }
      concatenated = base64Decode(cipherJson['payload'] as String);
    } catch (error) {
      if (error is BackupFormatException) rethrow;
      throw const BackupFormatException('Backup encryption metadata is invalid.');
    }
    if (salt.length != 16) {
      throw const BackupFormatException('Backup salt length is invalid.');
    }

    final kdf = Argon2id(
      memory: memoryKiB,
      parallelism: parallelism,
      iterations: iterations,
      hashLength: 32,
    );
    final secretKey = await kdf.deriveKeyFromPassword(
      password: passphrase,
      nonce: salt,
    );
    final cipher = AesGcm.with256bits();

    final Uint8List zipped;
    try {
      final secretBox = SecretBox.fromConcatenation(
        concatenated,
        nonceLength: cipher.nonceLength,
        macLength: cipher.macAlgorithm.macLength,
      );
      zipped = Uint8List.fromList(
        await cipher.decrypt(
          secretBox,
          secretKey: secretKey,
        ),
      );
    } catch (_) {
      throw const BackupFormatException('Incorrect passphrase or corrupted backup.');
    }
    if (zipped.isEmpty || zipped.length > maxBackupBytes) {
      throw const BackupFormatException('Decrypted backup payload size is invalid.');
    }

    final Archive archive;
    try {
      // AES-GCM already authenticates the complete compressed payload. Keep ZIP
      // decoding lazy here so untrusted metadata cannot force eager decompression.
      archive = ZipDecoder().decodeBytes(zipped);
    } catch (_) {
      throw const BackupFormatException('Backup archive is corrupted.');
    }

    if (archive.length > maxReceiptCount + 1) {
      throw const BackupFormatException('Backup archive contains too many entries.');
    }

    final entries = <String, ArchiveFile>{};
    for (final entry in archive) {
      if (!entry.isFile) continue;
      if (entries.containsKey(entry.name)) {
        throw const BackupFormatException('Backup archive contains duplicate file names.');
      }
      entries[entry.name] = entry;
    }

    final tripEntry = entries[_tripEntryName];
    if (tripEntry == null || tripEntry.size <= 0 || tripEntry.size > maxTripJsonBytes) {
      throw const BackupFormatException('Backup trip metadata is missing or invalid.');
    }

    final StoredTrip trip;
    try {
      final tripBytes = tripEntry.readBytes();
      if (tripBytes == null) throw const FormatException('Missing trip bytes.');
      final raw = jsonDecode(utf8.decode(tripBytes));
      if (raw is! Map) throw const FormatException('Expected a trip object.');
      trip = StoredTrip.fromJson(Map<String, dynamic>.from(raw));
    } catch (_) {
      throw const BackupFormatException('Backup trip metadata cannot be decoded.');
    }

    final receipts = <String, Uint8List>{};
    final expectedEntries = <String>{_tripEntryName};
    var receiptCount = 0;
    var totalReceiptBytes = 0;

    for (final expense in trip.expenses) {
      for (final receipt in expense.receipts) {
        receiptCount++;
        if (receiptCount > maxReceiptCount) {
          throw const BackupFormatException('Backup contains too many receipt files.');
        }
        final expectedPath = _receiptArchivePath(expense.id, receipt.id);
        if (receipt.localPath != expectedPath) {
          throw BackupFormatException('Receipt ${receipt.id} has an invalid archive path.');
        }
        expectedEntries.add(expectedPath);
        final entry = entries[expectedPath];
        if (entry == null || entry.size <= 0 || entry.size > maxReceiptBytes) {
          throw BackupFormatException('Receipt ${receipt.id} is missing or too large.');
        }
        totalReceiptBytes += entry.size;
        if (totalReceiptBytes > maxTotalReceiptBytes) {
          throw const BackupFormatException('Backup receipt data exceeds the safe restore limit.');
        }
        final data = entry.readBytes();
        if (data == null) {
          throw BackupFormatException('Receipt ${receipt.id} cannot be read.');
        }
        final digest = sha256.convert(data).toString();
        if (digest != receipt.sha256 || data.length != receipt.sizeBytes) {
          throw BackupFormatException('Receipt ${receipt.id} failed integrity validation.');
        }
        receipts[receipt.id] = Uint8List.fromList(data);
      }
    }

    final unexpected = entries.keys.where((name) => !expectedEntries.contains(name)).toList();
    if (unexpected.isNotEmpty) {
      throw const BackupFormatException('Backup archive contains unexpected files.');
    }

    return DecodedTripBackup(
      trip: trip,
      receiptBytesById: Map.unmodifiable(receipts),
      createdAtEpochMs: createdAtEpochMs,
    );
  }

  Map<String, Object?> _portableTripJson(StoredTrip trip) {
    final json = Map<String, Object?>.from(trip.toJson());
    json['expenses'] = <Object?>[
      for (final expense in trip.expenses)
        <String, Object?>{
          ...expense.toJson(),
          'receipts': <Object?>[
            for (final receipt in expense.receipts)
              <String, Object?>{
                ...receipt.toJson(),
                'localPath': _receiptArchivePath(expense.id, receipt.id),
              },
          ],
        },
    ];
    return json;
  }

  static String _receiptArchivePath(String expenseId, String receiptId) =>
      'receipts/$expenseId/$receiptId.bin';

  void _validatePassphrase(String passphrase) {
    if (passphrase.length < 8) {
      throw const BackupFormatException('Backup passphrase must contain at least 8 characters.');
    }
  }

  void _validateKdfParameters({
    required int memoryKiB,
    required int iterations,
    required int parallelism,
  }) {
    if (memoryKiB < 1024 || memoryKiB > 65536) {
      throw const BackupFormatException('Backup KDF memory setting is outside the supported range.');
    }
    if (iterations < 1 || iterations > 4) {
      throw const BackupFormatException('Backup KDF iteration setting is outside the supported range.');
    }
    if (parallelism < 1 || parallelism > 4) {
      throw const BackupFormatException('Backup KDF parallelism setting is outside the supported range.');
    }
  }

  Map<String, dynamic> _map(Object? raw, String label) {
    if (raw is! Map) {
      throw BackupFormatException('Backup $label is invalid.');
    }
    return Map<String, dynamic>.from(raw);
  }
}
