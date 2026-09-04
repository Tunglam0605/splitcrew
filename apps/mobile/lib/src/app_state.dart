import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:splitcrew_domain/splitcrew_domain.dart';
import 'package:splitcrew_settlement_engine/splitcrew_settlement_engine.dart';
import 'package:uuid/uuid.dart';

import 'local_store.dart';
import 'stored_models.dart';

export 'stored_models.dart';

final class TripController extends ChangeNotifier {
  static const _legacyStorageKey = 'splitcrew.trip.v1';

  TripController({TripRepository? repository, Uuid? uuid})
      : _repository = repository ?? SqliteTripRepository(),
        _uuid = uuid ?? const Uuid();

  final TripRepository _repository;
  final Uuid _uuid;
  StoredTrip? _trip;
  String? _loadError;

  StoredTrip? get trip => _trip;
  String? get loadError => _loadError;
  bool get hasTrip => _trip != null;

  Future<void> load() async {
    try {
      _trip = await _repository.loadCurrent();
      if (_trip == null) await _importLegacyPreferencesIfPresent();
      if (_trip != null) _validateStoredTrip(_trip!);
      _loadError = null;
    } catch (error) {
      _trip = null;
      _loadError = 'Saved trip could not be loaded: $error';
    }
    notifyListeners();
  }

  Future<void> createTrip({required String name, required String ownerName}) async {
    final cleanName = name.trim();
    final cleanOwner = ownerName.trim();
    if (cleanName.isEmpty || cleanOwner.isEmpty) {
      throw ArgumentError('Trip name and owner name are required.');
    }
    final now = _nowMs();
    final tripId = _uuid.v4();
    final ownerId = _uuid.v4();
    _trip = StoredTrip(
      id: tripId,
      name: cleanName,
      currencyCode: 'VND',
      members: [
        StoredMember(
          id: ownerId,
          name: cleanOwner,
          isOwner: true,
          createdAtMs: now,
          updatedAtMs: now,
        ),
      ],
      expenses: const [],
      createdAtMs: now,
      updatedAtMs: now,
    );
    await _persist();
    notifyListeners();
  }

  Future<void> renameTrip(String name) async {
    final current = _requireTrip();
    final clean = name.trim();
    if (clean.isEmpty) throw ArgumentError('Trip name is required.');
    _trip = _touchTrip(current, name: clean);
    await _persistAndNotify();
  }

  Future<void> addMember(String name) async {
    final current = _requireTrip();
    final clean = name.trim();
    _validateUniqueMemberName(current, clean);
    final now = _nowMs();
    _trip = _touchTrip(
      current,
      members: [
        ...current.members,
        StoredMember(
          id: _uuid.v4(),
          name: clean,
          isOwner: false,
          createdAtMs: now,
          updatedAtMs: now,
        ),
      ],
    );
    await _persistAndNotify();
  }

  Future<void> renameMember(String memberId, String name) async {
    final current = _requireTrip();
    final clean = name.trim();
    _validateUniqueMemberName(current, clean, exceptId: memberId);
    final member = current.members.where((item) => item.id == memberId).firstOrNull;
    if (member == null) throw ArgumentError('Member not found.');
    final updated = member.copyWith(name: clean, updatedAtMs: _nowMs(), version: member.version + 1);
    _trip = _touchTrip(
      current,
      members: [for (final item in current.members) if (item.id == memberId) updated else item],
    );
    await _persistAndNotify();
  }

  Future<void> removeMember(String memberId) async {
    final current = _requireTrip();
    final member = current.members.where((item) => item.id == memberId).firstOrNull;
    if (member == null) throw ArgumentError('Member not found.');
    if (member.isOwner) throw ArgumentError('The owner cannot be removed.');
    final referenced = current.expenses.any(
      (expense) => expense.payerMinorByMember.containsKey(memberId) || expense.allocationMinorByMember.containsKey(memberId),
    );
    if (referenced) {
      throw ArgumentError('This member is referenced by existing expenses. Edit or remove those expenses first.');
    }
    _trip = _touchTrip(
      current,
      members: current.members.where((item) => item.id != memberId).toList(),
    );
    await _persistAndNotify();
  }

  Future<void> addExpense({
    required String title,
    required int totalMinor,
    required List<ExpensePayer> payers,
    required List<ExpenseAllocation> allocations,
  }) async {
    final current = _requireTrip();
    final now = _nowMs();
    final stored = _validatedExpense(
      current: current,
      id: _uuid.v4(),
      title: title,
      totalMinor: totalMinor,
      payers: payers,
      allocations: allocations,
      createdAtMs: now,
      updatedAtMs: now,
      version: 0,
    );
    _trip = _touchTrip(current, expenses: [...current.expenses, stored]);
    await _persistAndNotify();
  }

  Future<void> updateExpense({
    required String expenseId,
    required String title,
    required int totalMinor,
    required List<ExpensePayer> payers,
    required List<ExpenseAllocation> allocations,
  }) async {
    final current = _requireTrip();
    final old = current.expenses.where((item) => item.id == expenseId).firstOrNull;
    if (old == null) throw ArgumentError('Expense not found.');
    final stored = _validatedExpense(
      current: current,
      id: old.id,
      title: title,
      totalMinor: totalMinor,
      payers: payers,
      allocations: allocations,
      createdAtMs: old.createdAtMs,
      updatedAtMs: _nowMs(),
      version: old.version + 1,
    );
    _trip = _touchTrip(
      current,
      expenses: [for (final expense in current.expenses) if (expense.id == expenseId) stored else expense],
    );
    await _persistAndNotify();
  }

  Future<void> removeExpense(String expenseId) async {
    final current = _requireTrip();
    if (!current.expenses.any((expense) => expense.id == expenseId)) return;
    _trip = _touchTrip(
      current,
      expenses: current.expenses.where((expense) => expense.id != expenseId).toList(),
    );
    await _persistAndNotify();
  }

  Future<void> reset() async {
    _trip = null;
    _loadError = null;
    await _repository.deleteCurrent();
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_legacyStorageKey);
    notifyListeners();
  }

  List<Expense> get domainExpenses {
    final current = _trip;
    if (current == null) return const [];
    return current.expenses
        .map((expense) => expense.toDomain(tripId: current.id, currencyCode: current.currencyCode))
        .toList(growable: false);
  }

  List<MemberBalance> get balances {
    final current = _trip;
    if (current == null) return const [];
    return SettlementEngine.calculateBalances(
      expenses: domainExpenses,
      memberIds: current.members.map((member) => member.id),
      currencyCode: current.currencyCode,
    );
  }

  List<SettlementTransfer> get settlements => SettlementEngine.settleBalances(balances);

  int get totalSpentMinor => _trip?.expenses.fold<int>(0, (sum, expense) => sum + expense.totalMinor) ?? 0;

  String memberName(String id) {
    final current = _trip;
    if (current == null) return id;
    for (final member in current.members) {
      if (member.id == id) return member.name;
    }
    return id;
  }

  StoredExpense? expenseById(String id) {
    final current = _trip;
    if (current == null) return null;
    return current.expenses.where((expense) => expense.id == id).firstOrNull;
  }

  StoredExpense _validatedExpense({
    required StoredTrip current,
    required String id,
    required String title,
    required int totalMinor,
    required List<ExpensePayer> payers,
    required List<ExpenseAllocation> allocations,
    required int createdAtMs,
    required int updatedAtMs,
    required int version,
  }) {
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) throw ArgumentError('Expense title is required.');
    if (totalMinor <= 0) throw ArgumentError('Expense total must be greater than zero.');
    if (payers.isEmpty) throw ArgumentError('At least one payer is required.');
    final memberIds = current.members.map((member) => member.id).toSet();
    final referencedIds = <String>{
      ...payers.map((payer) => payer.memberId),
      ...allocations.map((allocation) => allocation.memberId),
    };
    if (!memberIds.containsAll(referencedIds)) {
      throw ArgumentError('Expense references a member outside the trip.');
    }
    final createdBy = payers.first.memberId;
    final expense = Expense(
      id: id,
      tripId: current.id,
      title: cleanTitle,
      total: Money(minorUnits: totalMinor, currencyCode: current.currencyCode),
      payers: payers,
      allocations: allocations,
      createdByMemberId: createdBy,
      version: version,
    );
    return StoredExpense(
      id: expense.id,
      title: expense.title,
      totalMinor: expense.total.minorUnits,
      payerMinorByMember: {for (final payer in expense.payers) payer.memberId: payer.amount.minorUnits},
      allocationMinorByMember: {
        for (final allocation in expense.allocations) allocation.memberId: allocation.amount.minorUnits,
      },
      createdByMemberId: expense.createdByMemberId,
      createdAtMs: createdAtMs,
      updatedAtMs: updatedAtMs,
      version: version,
    );
  }

  StoredTrip _touchTrip(
    StoredTrip current, {
    String? name,
    List<StoredMember>? members,
    List<StoredExpense>? expenses,
  }) =>
      current.copyWith(
        name: name,
        members: members,
        expenses: expenses,
        updatedAtMs: _nowMs(),
        version: current.version + 1,
      );

  void _validateUniqueMemberName(StoredTrip current, String clean, {String? exceptId}) {
    if (clean.isEmpty) throw ArgumentError('Member name is required.');
    if (current.members.any(
      (member) => member.id != exceptId && member.name.toLowerCase() == clean.toLowerCase(),
    )) {
      throw ArgumentError('A member with this name already exists.');
    }
  }

  StoredTrip _requireTrip() {
    final current = _trip;
    if (current == null) throw StateError('No trip has been created.');
    return current;
  }

  void _validateStoredTrip(StoredTrip trip) {
    if (trip.id.isEmpty || trip.name.trim().isEmpty || trip.currencyCode.length != 3) {
      throw const FormatException('Invalid trip metadata.');
    }
    if (trip.members.isEmpty || !trip.members.any((member) => member.isOwner)) {
      throw const FormatException('Trip must contain an owner.');
    }
    final ids = trip.members.map((member) => member.id).toSet();
    if (ids.length != trip.members.length) throw const FormatException('Duplicate member identifiers.');
    for (final expense in trip.expenses) {
      expense.toDomain(tripId: trip.id, currencyCode: trip.currencyCode);
      if (!ids.containsAll(expense.payerMinorByMember.keys) || !ids.containsAll(expense.allocationMinorByMember.keys)) {
        throw const FormatException('Expense references an unknown member.');
      }
    }
  }

  Future<void> _persistAndNotify() async {
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    final current = _trip;
    if (current == null) {
      await _repository.deleteCurrent();
    } else {
      await _repository.save(current);
    }
  }

  Future<void> _importLegacyPreferencesIfPresent() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_legacyStorageKey);
    if (raw == null || raw.isEmpty) return;
    final decoded = StoredTrip.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
    final now = _nowMs();
    final normalized = StoredTrip(
      id: decoded.id,
      name: decoded.name,
      currencyCode: decoded.currencyCode,
      members: [
        for (final member in decoded.members)
          StoredMember(
            id: member.id,
            name: member.name,
            isOwner: member.isOwner,
            createdAtMs: member.createdAtMs == 0 ? now : member.createdAtMs,
            updatedAtMs: member.updatedAtMs == 0 ? now : member.updatedAtMs,
            version: member.version,
          ),
      ],
      expenses: [
        for (final expense in decoded.expenses)
          StoredExpense(
            id: expense.id,
            title: expense.title,
            totalMinor: expense.totalMinor,
            payerMinorByMember: expense.payerMinorByMember,
            allocationMinorByMember: expense.allocationMinorByMember,
            createdByMemberId: expense.createdByMemberId,
            createdAtMs: expense.createdAtMs == 0 ? now : expense.createdAtMs,
            updatedAtMs: expense.updatedAtMs == 0 ? now : expense.updatedAtMs,
            version: expense.version,
          ),
      ],
      createdAtMs: decoded.createdAtMs == 0 ? now : decoded.createdAtMs,
      updatedAtMs: decoded.updatedAtMs == 0 ? now : decoded.updatedAtMs,
      version: decoded.version,
    );
    _validateStoredTrip(normalized);
    await _repository.save(normalized);
    await preferences.remove(_legacyStorageKey);
    _trip = normalized;
  }

  int _nowMs() => DateTime.now().millisecondsSinceEpoch;
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
