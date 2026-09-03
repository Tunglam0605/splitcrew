import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:splitcrew_domain/splitcrew_domain.dart';
import 'package:splitcrew_settlement_engine/splitcrew_settlement_engine.dart';

final class StoredMember {
  const StoredMember({required this.id, required this.name, required this.isOwner});

  final String id;
  final String name;
  final bool isOwner;

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'isOwner': isOwner};

  factory StoredMember.fromJson(Map<String, dynamic> json) => StoredMember(
        id: json['id'] as String,
        name: json['name'] as String,
        isOwner: json['isOwner'] as bool? ?? false,
      );
}

final class StoredExpense {
  StoredExpense({
    required this.id,
    required this.title,
    required this.totalMinor,
    required Map<String, int> payerMinorByMember,
    required Map<String, int> allocationMinorByMember,
    required this.createdByMemberId,
  })  : payerMinorByMember = Map.unmodifiable(payerMinorByMember),
        allocationMinorByMember = Map.unmodifiable(allocationMinorByMember);

  final String id;
  final String title;
  final int totalMinor;
  final Map<String, int> payerMinorByMember;
  final Map<String, int> allocationMinorByMember;
  final String createdByMemberId;

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'totalMinor': totalMinor,
        'payers': payerMinorByMember,
        'allocations': allocationMinorByMember,
        'createdByMemberId': createdByMemberId,
      };

  factory StoredExpense.fromJson(Map<String, dynamic> json) => StoredExpense(
        id: json['id'] as String,
        title: json['title'] as String,
        totalMinor: json['totalMinor'] as int,
        payerMinorByMember: _intMap(json['payers']),
        allocationMinorByMember: _intMap(json['allocations']),
        createdByMemberId: json['createdByMemberId'] as String,
      );

  Expense toDomain({required String tripId, required String currencyCode}) {
    return Expense(
      id: id,
      tripId: tripId,
      title: title,
      total: Money(minorUnits: totalMinor, currencyCode: currencyCode),
      payers: [
        for (final entry in payerMinorByMember.entries)
          ExpensePayer(
            memberId: entry.key,
            amount: Money(minorUnits: entry.value, currencyCode: currencyCode),
          ),
      ],
      allocations: [
        for (final entry in allocationMinorByMember.entries)
          ExpenseAllocation(
            memberId: entry.key,
            amount: Money(minorUnits: entry.value, currencyCode: currencyCode),
          ),
      ],
      createdByMemberId: createdByMemberId,
    );
  }
}

final class StoredTrip {
  StoredTrip({
    required this.id,
    required this.name,
    required this.currencyCode,
    required List<StoredMember> members,
    required List<StoredExpense> expenses,
  })  : members = List.unmodifiable(members),
        expenses = List.unmodifiable(expenses);

  final String id;
  final String name;
  final String currencyCode;
  final List<StoredMember> members;
  final List<StoredExpense> expenses;

  StoredTrip copyWith({
    String? name,
    List<StoredMember>? members,
    List<StoredExpense>? expenses,
  }) {
    return StoredTrip(
      id: id,
      name: name ?? this.name,
      currencyCode: currencyCode,
      members: members ?? this.members,
      expenses: expenses ?? this.expenses,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'currencyCode': currencyCode,
        'members': members.map((member) => member.toJson()).toList(),
        'expenses': expenses.map((expense) => expense.toJson()).toList(),
      };

  factory StoredTrip.fromJson(Map<String, dynamic> json) => StoredTrip(
        id: json['id'] as String,
        name: json['name'] as String,
        currencyCode: json['currencyCode'] as String? ?? 'VND',
        members: (json['members'] as List<dynamic>)
            .map((item) => StoredMember.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList(),
        expenses: (json['expenses'] as List<dynamic>? ?? const [])
            .map((item) => StoredExpense.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList(),
      );
}

final class TripController extends ChangeNotifier {
  static const _storageKey = 'splitcrew.trip.v1';

  SharedPreferences? _preferences;
  StoredTrip? _trip;
  String? _loadError;

  StoredTrip? get trip => _trip;
  String? get loadError => _loadError;
  bool get hasTrip => _trip != null;

  Future<void> load() async {
    try {
      _preferences = await SharedPreferences.getInstance();
      final raw = _preferences!.getString(_storageKey);
      if (raw != null && raw.isNotEmpty) {
        _trip = StoredTrip.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
        _validateStoredTrip(_trip!);
      }
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
    final tripId = _newId('trip');
    final ownerId = _newId('member');
    _trip = StoredTrip(
      id: tripId,
      name: cleanName,
      currencyCode: 'VND',
      members: [StoredMember(id: ownerId, name: cleanOwner, isOwner: true)],
      expenses: const [],
    );
    await _persist();
    notifyListeners();
  }

  Future<void> addMember(String name) async {
    final current = _requireTrip();
    final clean = name.trim();
    if (clean.isEmpty) throw ArgumentError('Member name is required.');
    if (current.members.any((member) => member.name.toLowerCase() == clean.toLowerCase())) {
      throw ArgumentError('A member with this name already exists.');
    }
    _trip = current.copyWith(
      members: [...current.members, StoredMember(id: _newId('member'), name: clean, isOwner: false)],
    );
    await _persist();
    notifyListeners();
  }

  Future<void> addExpense({
    required String title,
    required int totalMinor,
    required List<ExpensePayer> payers,
    required List<ExpenseAllocation> allocations,
  }) async {
    final current = _requireTrip();
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

    final id = _newId('expense');
    final createdBy = payers.first.memberId;
    final expense = Expense(
      id: id,
      tripId: current.id,
      title: cleanTitle,
      total: Money(minorUnits: totalMinor, currencyCode: current.currencyCode),
      payers: payers,
      allocations: allocations,
      createdByMemberId: createdBy,
    );

    final stored = StoredExpense(
      id: expense.id,
      title: expense.title,
      totalMinor: expense.total.minorUnits,
      payerMinorByMember: {for (final payer in expense.payers) payer.memberId: payer.amount.minorUnits},
      allocationMinorByMember: {
        for (final allocation in expense.allocations) allocation.memberId: allocation.amount.minorUnits,
      },
      createdByMemberId: expense.createdByMemberId,
    );
    _trip = current.copyWith(expenses: [...current.expenses, stored]);
    await _persist();
    notifyListeners();
  }

  Future<void> removeExpense(String expenseId) async {
    final current = _requireTrip();
    _trip = current.copyWith(
      expenses: current.expenses.where((expense) => expense.id != expenseId).toList(),
    );
    await _persist();
    notifyListeners();
  }

  Future<void> reset() async {
    _trip = null;
    _loadError = null;
    await _preferences?.remove(_storageKey);
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
    for (final expense in trip.expenses) {
      expense.toDomain(tripId: trip.id, currencyCode: trip.currencyCode);
    }
  }

  Future<void> _persist() async {
    _preferences ??= await SharedPreferences.getInstance();
    final current = _trip;
    if (current == null) {
      await _preferences!.remove(_storageKey);
      return;
    }
    await _preferences!.setString(_storageKey, jsonEncode(current.toJson()));
  }

  String _newId(String prefix) => '$prefix-${DateTime.now().microsecondsSinceEpoch}';
}

Map<String, int> _intMap(Object? raw) {
  final map = Map<String, dynamic>.from(raw as Map);
  return map.map((key, value) => MapEntry(key, value as int));
}
