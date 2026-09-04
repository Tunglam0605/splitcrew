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

final class StoredPaymentAccount {
  const StoredPaymentAccount({
    required this.id,
    required this.memberId,
    required this.provider,
    required this.holderName,
    required this.routingIdentifier,
    required this.accountIdentifier,
    this.createdAtMs = 0,
    this.updatedAtMs = 0,
    this.version = 0,
  });

  final String id;
  final String memberId;
  final PaymentAccountProvider provider;
  final String holderName;
  final String routingIdentifier;
  final String accountIdentifier;
  final int createdAtMs;
  final int updatedAtMs;
  final int version;

  PaymentAccount toDomain() => PaymentAccount(
        id: id,
        memberId: memberId,
        provider: provider,
        holderName: holderName,
        routingIdentifier: routingIdentifier,
        accountIdentifier: accountIdentifier,
        version: version,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'memberId': memberId,
        'provider': provider.name,
        'holderName': holderName,
        'routingIdentifier': routingIdentifier,
        'accountIdentifier': accountIdentifier,
        'createdAtMs': createdAtMs,
        'updatedAtMs': updatedAtMs,
        'version': version,
      };

  factory StoredPaymentAccount.fromJson(Map<String, dynamic> json) => StoredPaymentAccount(
        id: json['id'] as String,
        memberId: json['memberId'] as String,
        provider: PaymentAccountProvider.values.byName(json['provider'] as String? ?? 'vietQrBank'),
        holderName: json['holderName'] as String,
        routingIdentifier: json['routingIdentifier'] as String,
        accountIdentifier: json['accountIdentifier'] as String,
        createdAtMs: json['createdAtMs'] as int? ?? 0,
        updatedAtMs: json['updatedAtMs'] as int? ?? 0,
        version: json['version'] as int? ?? 0,
      );
}

final class StoredReceiptAsset {
  const StoredReceiptAsset({
    required this.id,
    required this.expenseId,
    required this.localPath,
    required this.sha256,
    required this.originalName,
    required this.mimeType,
    required this.sizeBytes,
    this.createdAtMs = 0,
    this.version = 0,
  });

  final String id;
  final String expenseId;
  final String localPath;
  final String sha256;
  final String originalName;
  final String mimeType;
  final int sizeBytes;
  final int createdAtMs;
  final int version;

  Map<String, Object?> toJson() => {
        'id': id,
        'expenseId': expenseId,
        'localPath': localPath,
        'sha256': sha256,
        'originalName': originalName,
        'mimeType': mimeType,
        'sizeBytes': sizeBytes,
        'createdAtMs': createdAtMs,
        'version': version,
      };

  factory StoredReceiptAsset.fromJson(Map<String, dynamic> json) => StoredReceiptAsset(
        id: json['id'] as String,
        expenseId: json['expenseId'] as String,
        localPath: json['localPath'] as String,
        sha256: json['sha256'] as String,
        originalName: json['originalName'] as String? ?? 'receipt',
        mimeType: json['mimeType'] as String? ?? 'image/jpeg',
        sizeBytes: json['sizeBytes'] as int? ?? 0,
        createdAtMs: json['createdAtMs'] as int? ?? 0,
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
    List<StoredReceiptAsset> receipts = const [],
    this.createdAtMs = 0,
    this.updatedAtMs = 0,
    this.version = 0,
  })  : payerMinorByMember = Map.unmodifiable(payerMinorByMember),
        allocationMinorByMember = Map.unmodifiable(allocationMinorByMember),
        receipts = List.unmodifiable(receipts);

  final String id;
  final String title;
  final int totalMinor;
  final Map<String, int> payerMinorByMember;
  final Map<String, int> allocationMinorByMember;
  final String createdByMemberId;
  final List<StoredReceiptAsset> receipts;
  final int createdAtMs;
  final int updatedAtMs;
  final int version;

  StoredExpense copyWith({
    String? title,
    int? totalMinor,
    Map<String, int>? payerMinorByMember,
    Map<String, int>? allocationMinorByMember,
    List<StoredReceiptAsset>? receipts,
    int? updatedAtMs,
    int? version,
  }) =>
      StoredExpense(
        id: id,
        title: title ?? this.title,
        totalMinor: totalMinor ?? this.totalMinor,
        payerMinorByMember: payerMinorByMember ?? this.payerMinorByMember,
        allocationMinorByMember: allocationMinorByMember ?? this.allocationMinorByMember,
        createdByMemberId: createdByMemberId,
        receipts: receipts ?? this.receipts,
        createdAtMs: createdAtMs,
        updatedAtMs: updatedAtMs ?? this.updatedAtMs,
        version: version ?? this.version,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'totalMinor': totalMinor,
        'payers': payerMinorByMember,
        'allocations': allocationMinorByMember,
        'createdByMemberId': createdByMemberId,
        'receipts': receipts.map((receipt) => receipt.toJson()).toList(),
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
        receipts: (json['receipts'] as List<dynamic>? ?? const [])
            .map((item) => StoredReceiptAsset.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList(),
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
    List<StoredPaymentAccount> paymentAccounts = const [],
    this.createdAtMs = 0,
    this.updatedAtMs = 0,
    this.version = 0,
  })  : members = List.unmodifiable(members),
        expenses = List.unmodifiable(expenses),
        paymentAccounts = List.unmodifiable(paymentAccounts);

  final String id;
  final String name;
  final String currencyCode;
  final List<StoredMember> members;
  final List<StoredExpense> expenses;
  final List<StoredPaymentAccount> paymentAccounts;
  final int createdAtMs;
  final int updatedAtMs;
  final int version;

  StoredTrip copyWith({
    String? name,
    List<StoredMember>? members,
    List<StoredExpense>? expenses,
    List<StoredPaymentAccount>? paymentAccounts,
    int? updatedAtMs,
    int? version,
  }) {
    return StoredTrip(
      id: id,
      name: name ?? this.name,
      currencyCode: currencyCode,
      members: members ?? this.members,
      expenses: expenses ?? this.expenses,
      paymentAccounts: paymentAccounts ?? this.paymentAccounts,
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
        'paymentAccounts': paymentAccounts.map((account) => account.toJson()).toList(),
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
        paymentAccounts: (json['paymentAccounts'] as List<dynamic>? ?? const [])
            .map((item) => StoredPaymentAccount.fromJson(Map<String, dynamic>.from(item as Map)))
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
