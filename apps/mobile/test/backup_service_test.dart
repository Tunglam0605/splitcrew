import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:splitcrew_domain/splitcrew_domain.dart';
import 'package:splitcrew_mobile/src/app_state.dart';
import 'package:splitcrew_mobile/src/backup_codec.dart';
import 'package:splitcrew_mobile/src/backup_service.dart';
import 'package:splitcrew_mobile/src/local_store.dart';
import 'package:splitcrew_mobile/src/receipt_store.dart';
import 'package:splitcrew_mobile/src/stored_models.dart';
import 'package:splitcrew_split_engine/splitcrew_split_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('restore replaces canonical trip and cleans superseded receipt files', () async {
    final repository = MemoryTripRepository();
    final receiptStore = MemoryReceiptFileStore();
    final controller = TripController(
      repository: repository,
      receiptFileStore: receiptStore,
    );
    await controller.load();
    await controller.createTrip(name: 'Old trip', ownerName: 'Old owner');

    final oldOwner = controller.trip!.members.single;
    const oldTotal = Money(minorUnits: 50000, currencyCode: 'VND');
    await controller.addExpense(
      title: 'Old expense',
      totalMinor: oldTotal.minorUnits,
      payers: [ExpensePayer(memberId: oldOwner.id, amount: oldTotal)],
      allocations: SplitEngine.equal(
        total: oldTotal,
        memberIds: [oldOwner.id],
      ),
    );
    final oldExpenseId = controller.trip!.expenses.single.id;
    await controller.addReceiptFromPath(
      expenseId: oldExpenseId,
      sourcePath: '/memory/old.jpg',
      originalName: 'old.jpg',
      mimeType: 'image/jpeg',
    );
    final oldReceiptId = controller.expenseById(oldExpenseId)!.receipts.single.id;

    final restoredBytes = Uint8List.fromList(const [10, 20, 30, 40, 50]);
    final restoredReceipt = StoredReceiptAsset(
      id: 'receipt-new',
      expenseId: 'expense-new',
      localPath: 'receipts/expense-new/receipt-new.bin',
      sha256: sha256.convert(restoredBytes).toString(),
      originalName: 'restored.jpg',
      mimeType: 'image/jpeg',
      sizeBytes: restoredBytes.length,
      createdAtMs: 200,
    );
    final restoredOwner = const StoredMember(
      id: 'owner-new',
      name: 'New owner',
      isOwner: true,
      createdAtMs: 100,
      updatedAtMs: 100,
    );
    final restoredExpense = StoredExpense(
      id: 'expense-new',
      title: 'Restored expense',
      totalMinor: 90000,
      payerMinorByMember: const {'owner-new': 90000},
      allocationMinorByMember: const {'owner-new': 90000},
      createdByMemberId: 'owner-new',
      receipts: [restoredReceipt],
      createdAtMs: 200,
      updatedAtMs: 200,
    );
    final restoredTrip = StoredTrip(
      id: 'trip-new',
      name: 'Recovered trip',
      currencyCode: 'VND',
      members: [restoredOwner],
      expenses: [restoredExpense],
      createdAtMs: 100,
      updatedAtMs: 200,
      version: 7,
    );
    final decoded = DecodedTripBackup(
      trip: restoredTrip,
      receiptBytesById: {'receipt-new': restoredBytes},
      createdAtEpochMs: 300,
    );

    final service = TripBackupService(
      controller: controller,
      receiptFileStore: receiptStore,
      codec: TripBackupCodec(
        kdfMemoryKiB: 1024,
        kdfIterations: 1,
        kdfParallelism: 1,
      ),
    );
    final result = await service.restoreDecoded(decoded);

    expect(result.id, 'trip-new');
    expect(controller.trip!.id, 'trip-new');
    expect(controller.trip!.name, 'Recovered trip');
    expect(controller.trip!.expenses.single.title, 'Restored expense');

    final managedReceipt = controller.trip!.expenses.single.receipts.single;
    expect(managedReceipt.id, 'receipt-new');
    expect(managedReceipt.localPath, '/memory/expense-new/receipt-new');
    expect(
      await receiptStore.readBytes(managedReceipt),
      orderedEquals(restoredBytes),
    );
    expect(receiptStore.deletedIds, contains(oldReceiptId));

    final reloaded = TripController(
      repository: repository,
      receiptFileStore: receiptStore,
    );
    await reloaded.load();
    expect(reloaded.trip!.id, 'trip-new');
    expect(reloaded.trip!.expenses.single.receipts.single.id, 'receipt-new');
  });
}
