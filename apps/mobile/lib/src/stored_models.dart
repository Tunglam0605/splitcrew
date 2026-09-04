import 'package:splitcrew_domain/splitcrew_domain.dart';

final class StoredMember {
  const StoredMember({
    required this.id,
    required this.name,
    required this.isOwner,
    this.createdAtMs = 0,
    this.updatedAtMs = 0,
    this.version = 0,
  });

  final String id;
  final String name;
  final bool isOwner;
  final int createdAtMs;
  final int updatedAtMs;
  final int version;

  StoredMember copyWith({String? name, int? updatedAtMs, int? version}) => StoredMember(
        id: id,
        name: name ?? this.name,
        isOwner: isOwner,
        createdAtMs: createdAtMs,
        updatedAtMs: updatedAtMs ?? this.updatedAtMs,
        version: version ?? this.version,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'isOwner': isOwner,
        'createdAtMs': createdAtMs,
        'updatedAtMs': updatedAtMs,
        'version': version,
      };

  factory StoredMember.fromJson(Map<String, dynamic> json) => StoredMember(
        id: json['id'] as String,
        name: json['name'] as String,
        isOwner: json['isOwner'] as bool? ?? false,
        createdAtMs: json['createdAtMs'] as int? ?? 0,
        updatedAtMs: json['updatedAtMs'] as int? ?? 0,
        version: json['version'] as int? ?? 0,
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
    this.createdAtMs = 0,
    this.updatedAtMs = 0,
    this.version = 0,
  })  : payerMinorByMember = Map.unmodifiable(payerMinorByMember),
        allocationMinorByMember = Map.unmodifiable(allocationMinorByMember);

  final String id;
  final String title;
  final int totalMinor;
  final Map<String, int> payerMinorByMember;
  final Map<String, int> allocationMinorByMember;
  final String createdByMemberId;
  final int createdAtMs;
  final int updatedAtMs;
  final int version;

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'totalMinor': totalMinor,
        'payers': payerMinorByMember,
        'allocations': allocationMinorByMember,
        'createdByMemberId': createdByMemberId,
        'createdAtMs': createdAtMs,
        'updatedAtMs': updatedAtMs,
        'version': version,
      };

  factory StoredExpense.fromJson(Map<String, dynamic> json) => StoredExpense(
        id: json['id'] as String,
        title: json['title'] as String,
        totalMinor: json['totalMinor'] as int,
        payerMinorByMember: _intMap(json['payers']),
        allocationMinorByMember: _intMap(json['allocations']),
        createdByMemberId: json['createdByMemberId'] as String,
        createdAtMs: json['createdAtMs'] as int? ?? 0,
        updatedAtMs: json['updatedAtMs'] as int? ?? 0,
        version: json['version'] as int? ?? 0,
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
      version: version,
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
    this.createdAtMs = 0,
    this.updatedAtMs = 0,
    this.version = 0,
  })  : members = List.unmodifiable(members),
        expenses = List.unmodifiable(expenses);

  final String id;
  final String name;
  final String currencyCode;
  final List<StoredMember> members;
  final List<StoredExpense> expenses;
  final int createdAtMs;
  final int updatedAtMs;
  final int version;

  StoredTrip copyWith({
    String? name,
    List<StoredMember>? members,
    List<StoredExpense>? expenses,
    int? updatedAtMs,
    int? version,
  }) {
    return StoredTrip(
      id: id,
      name: name ?? this.name,
      currencyCode: currencyCode,
      members: members ?? this.members,
      expenses: expenses ?? this.expenses,
      createdAtMs: createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      version: version ?? this.version,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'currencyCode': currencyCode,
        'members': members.map((member) => member.toJson()).toList(),
        'expenses': expenses.map((expense) => expense.toJson()).toList(),
        'createdAtMs': createdAtMs,
        'updatedAtMs': updatedAtMs,
        'version': version,
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
        createdAtMs: json['createdAtMs'] as int? ?? 0,
        updatedAtMs: json['updatedAtMs'] as int? ?? 0,
        version: json['version'] as int? ?? 0,
      );
}

Map<String, int> _intMap(Object? raw) {
  final map = Map<String, dynamic>.from(raw as Map);
  return map.map((key, value) => MapEntry(key, value as int));
}
