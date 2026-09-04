import 'package:flutter_test/flutter_test.dart';
import 'package:splitcrew_domain/splitcrew_domain.dart';
import 'package:splitcrew_mobile/src/app_state.dart';
import 'package:splitcrew_mobile/src/local_store.dart';
import 'package:splitcrew_mobile/src/receipt_store.dart';
import 'package:splitcrew_split_engine/splitcrew_split_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(TripController, MemoryTripRepository, MemoryReceiptFileStore)> seeded() async {
    final repository = MemoryTripRepository();
    final receipts = MemoryReceiptFileStore();
    final controller = TripController(
      repository: repository,
      receiptFileStore: receipts,
    );
    await controller.load();
    await controller.createTrip(name: 'Da Nang', ownerName: 'Lam');
    await controller.addMember('Hoang');
    final members = controller.trip!.members;
    const total = Money(minorUnits: 100000, currencyCode: 'VND');
    await controller.addExpense(
      title: 'Dinner',
      totalMinor: total.minorUnits,
      payers: [ExpensePayer(memberId: members.first.id, amount: total)],
      allocations: SplitEngine.equal(total: total, memberIds: members.map((m) => m.id)),
    );
    return (controller, repository, receipts);
  }

  test('receipt metadata persists through repository reload', () async {
    final (controller, repository, receipts) = await seeded();
    final expenseId = controller.trip!.expenses.single.id;

    await controller.addReceiptFromPath(
      expenseId: expenseId,
      sourcePath: '/tmp/test-receipt.jpg',
      originalName: 'receipt.jpg',
      mimeType: 'image/jpeg',
    );

    expect(controller.expenseById(expenseId)!.receipts, hasLength(1));
    expect(controller.expenseById(expenseId)!.receipts.single.sha256, hasLength(64));

    final reloaded = TripController(
      repository: repository,
      receiptFileStore: receipts,
    );
    await reloaded.load();
    expect(reloaded.expenseById(expenseId)!.receipts.single.originalName, 'receipt.jpg');
  });

  test('editing financial fields preserves attached receipts', () async {
    final (controller, _, _) = await seeded();
    final expense = controller.trip!.expenses.single;
    await controller.addReceiptFromPath(
      expenseId: expense.id,
      sourcePath: '/tmp/test-receipt.jpg',
      originalName: 'receipt.jpg',
      mimeType: 'image/jpeg',
    );
    final members = controller.trip!.members;
    const updatedTotal = Money(minorUnits: 200000, currencyCode: 'VND');

    await controller.updateExpense(
      expenseId: expense.id,
      title: 'Updated dinner',
      totalMinor: updatedTotal.minorUnits,
      payers: [ExpensePayer(memberId: members.first.id, amount: updatedTotal)],
      allocations: SplitEngine.equal(total: updatedTotal, memberIds: members.map((m) => m.id)),
    );

    final updated = controller.expenseById(expense.id)!;
    expect(updated.title, 'Updated dinner');
    expect(updated.receipts, hasLength(1));
  });

  test('removing receipt commits metadata removal then cleans local file', () async {
    final (controller, _, receipts) = await seeded();
    final expenseId = controller.trip!.expenses.single.id;
    await controller.addReceiptFromPath(
      expenseId: expenseId,
      sourcePath: '/tmp/test-receipt.jpg',
      originalName: 'receipt.jpg',
      mimeType: 'image/jpeg',
    );
    final receiptId = controller.expenseById(expenseId)!.receipts.single.id;

    await controller.removeReceipt(expenseId: expenseId, receiptId: receiptId);

    expect(controller.expenseById(expenseId)!.receipts, isEmpty);
    expect(receipts.deletedIds, contains(receiptId));
  });

  test('deleting expense cleans every attached receipt file', () async {
    final (controller, _, receipts) = await seeded();
    final expenseId = controller.trip!.expenses.single.id;
    await controller.addReceiptFromPath(
      expenseId: expenseId,
      sourcePath: '/tmp/a.jpg',
      originalName: 'a.jpg',
      mimeType: 'image/jpeg',
    );
    await controller.addReceiptFromPath(
      expenseId: expenseId,
      sourcePath: '/tmp/b.jpg',
      originalName: 'b.jpg',
      mimeType: 'image/jpeg',
    );
    final ids = controller.expenseById(expenseId)!.receipts.map((receipt) => receipt.id).toSet();

    await controller.removeExpense(expenseId);

    expect(controller.expenseById(expenseId), isNull);
    expect(receipts.deletedIds, containsAll(ids));
  });
}
