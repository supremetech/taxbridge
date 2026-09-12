class DailySummary {
  DailySummary({
    required this.revenue,
    required this.expense,
    required this.collected,
    required this.receivable,
  });

  final int revenue;
  final int expense;
  final int collected;
  final int receivable;

  factory DailySummary.fromJson(Map<String, dynamic> j) => DailySummary(
    revenue: (j['revenue'] as num).toInt(),
    expense: (j['expense'] as num).toInt(),
    collected: (j['collected'] as num).toInt(),
    receivable: (j['receivable'] as num).toInt(),
  );

  Map<String, dynamic> toJson() => {
    'revenue': revenue,
    'expense': expense,
    'collected': collected,
    'receivable': receivable,
  };
}

class DailyWarning {
  DailyWarning({
    required this.warningId,
    required this.type,
    required this.status,
    required this.resourceType,
    required this.resourceId,
    this.amount,
    required this.message,
    this.resolvedAt,
  });

  final String warningId;
  final String type; // UNMATCHED_MONEY | DRAFT_EVENT
  final String status; // OPEN | RESOLVED
  final String resourceType; // EVENT | MONEY_MOVEMENT
  final String resourceId;
  final int? amount;
  final String message;
  final DateTime? resolvedAt;

  bool get isOpen => status == 'OPEN';

  /// Route tới màn xử lý warning.
  String get route => resourceType == 'MONEY_MOVEMENT'
      ? '/movements/$resourceId'
      : '/events/$resourceId';

  factory DailyWarning.fromJson(Map<String, dynamic> j) => DailyWarning(
    warningId: j['warningId'] as String,
    type: j['type'] as String,
    status: j['status'] as String,
    resourceType: j['resourceType'] as String,
    resourceId: j['resourceId'] as String,
    amount: (j['amount'] as num?)?.toInt(),
    message: j['message'] as String? ?? '',
    resolvedAt: DateTime.tryParse(j['resolvedAt'] as String? ?? ''),
  );

  Map<String, dynamic> toJson() => {
    'warningId': warningId,
    'type': type,
    'status': status,
    'resourceType': resourceType,
    'resourceId': resourceId,
    'amount': amount,
    'message': message,
    'resolvedAt': resolvedAt?.toIso8601String(),
  };
}

class DailyRecord {
  DailyRecord({
    required this.date,
    required this.summary,
    required this.warningCount,
    required this.warnings,
    this.closedAt,
    this.updatedAt,
  });

  final String date;
  final DailySummary summary;
  final int warningCount;
  final List<DailyWarning> warnings;
  final DateTime? closedAt;
  final DateTime? updatedAt;

  int get openCount => warnings.where((w) => w.isOpen).length;

  factory DailyRecord.fromJson(Map<String, dynamic> j) => DailyRecord(
    date: j['date'] as String,
    summary: DailySummary.fromJson(j['summary'] as Map<String, dynamic>),
    warningCount: (j['warningCount'] as num?)?.toInt() ?? 0,
    warnings: ((j['warnings'] as List?) ?? const [])
        .map((w) => DailyWarning.fromJson(w as Map<String, dynamic>))
        .toList(),
    closedAt: DateTime.tryParse(j['closedAt'] as String? ?? ''),
    updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? ''),
  );

  Map<String, dynamic> toJson() => {
    'date': date,
    'summary': summary.toJson(),
    'warningCount': warningCount,
    'warnings': warnings.map((w) => w.toJson()).toList(),
    'closedAt': closedAt?.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
  };
}
