import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:splitcrew_mobile/src/backup_codec.dart';
import 'package:splitcrew_mobile/src/stored_models.dart';

void main() {
  TripBackupCodec codec() => TripBackupCodec(
        kdfMemoryKiB: 1024,
        kdfIterations: 1,
        kdfParallelism: 1,
      );

  (StoredTrip, Uint8List) fixture() {
    final bytes = Uint8List.fromList(List<int>.generate(128, (index) => index));
    final owner = const StoredMember(
      id: 'owner-1',
      name: 'Lam',
      isOwner: true,
      createdAtMs: 10,
      updatedAtMs: 10,
    );
    final member = const StoredMember(
      id: 'member-1',
      name: 'An',
      isOwner: false,
      createdAtMs: 11,
      updatedAtMs: 11,
    );
    final receipt = StoredReceiptAsset(
      id: 'receipt-1',
      expenseId: 'expense-1',
      localPath: '/device/receipt.jpg',
      sha256: sha256.convert(bytes).toString(),
      originalName: 'bill.jpg',
      mimeType: 'image/jpeg',
      sizeBytes: bytes.length,
      createdAtMs: 12,
    );
    final expense = StoredExpense(
      id: 'expense-1',
      title: 'Secret dinner',
      totalMinor: 100000,
      payerMinorByMember: const {'owner-1': 100000},
      allocationMinorByMember: const {
        'owner-1': 50000,
        'member-1': 50000,
      },
      createdByMemberId: 'owner-1',
      receipts: [receipt],
      createdAtMs: 12,
      updatedAtMs: 12,
    );
    final trip = StoredTrip(
      id: 'trip-1',
      name: 'Da Nang',
      currencyCode: 'VND',
      members: [owner, member],
      expenses: [expense],
      createdAtMs: 10,
      updatedAtMs: 12,
      version: 3,
    );
    return (trip, bytes);
  }

  test('encrypted backup round-trips trip metadata and receipt bytes', () async {
    final (trip, receiptBytes) = fixture();
    final encoded = await codec().encode(
      trip: trip,
      receiptBytesById: {'receipt-1': receiptBytes},
      passphrase: 'correct horse battery staple',
    );

    final outerText = utf8.decode(encoded);
    expect(outerText, isNot(contains('Secret dinner')));
    expect(outerText, isNot(contains('Da Nang')));

    final decoded = await codec().decode(
      bytes: encoded,
      passphrase: 'correct horse battery staple',
    );

    expect(decoded.trip.id, trip.id);
    expect(decoded.trip.name, trip.name);
    expect(decoded.trip.expenses.single.title, 'Secret dinner');
    expect(
      decoded.trip.expenses.single.receipts.single.localPath,
      'receipts/expense-1/receipt-1.bin',
    );
    expect(decoded.receiptBytesById['receipt-1'], orderedEquals(receiptBytes));
  });

  test('wrong passphrase cannot decrypt backup', () async {
    final (trip, receiptBytes) = fixture();
    final encoded = await codec().encode(
      trip: trip,
      receiptBytesById: {'receipt-1': receiptBytes},
      passphrase: 'correct passphrase',
    );

    await expectLater(
      codec().decode(bytes: encoded, passphrase: 'wrong passphrase'),
      throwsA(isA<BackupFormatException>()),
    );
  });

  test('authenticated encryption rejects a modified ciphertext', () async {
    final (trip, receiptBytes) = fixture();
    final encoded = await codec().encode(
      trip: trip,
      receiptBytesById: {'receipt-1': receiptBytes},
      passphrase: 'correct passphrase',
    );

    final envelope = Map<String, dynamic>.from(
      jsonDecode(utf8.decode(encoded)) as Map,
    );
    final cipher = Map<String, dynamic>.from(envelope['cipher'] as Map);
    final payload = base64Decode(cipher['payload'] as String);
    payload[payload.length ~/ 2] ^= 0x01;
    cipher['payload'] = base64Encode(payload);
    envelope['cipher'] = cipher;
    final tampered = Uint8List.fromList(utf8.encode(jsonEncode(envelope)));

    await expectLater(
      codec().decode(bytes: tampered, passphrase: 'correct passphrase'),
      throwsA(isA<BackupFormatException>()),
    );
  });
}
