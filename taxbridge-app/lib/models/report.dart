/// `GET /api/reports?from&to` — Phase 2 ④ (`fixtures/report.json`).
class ReportSummary {
  ReportSummary({
    required this.revenue,
    required this.expense,
    required this.collected,
    required this.receivable,
    required this.bankIn,
    required this.saleCount,
    required this.purchaseCount,
    required this.draftCount,
    required this.unmatchedMoneyCount,
  });

  final int revenue;
  final int expense;
  final int collected;
  final int receivable;
  final int bankIn;
  final int saleCount;
  final int purchaseCount;
  final int draftCount;
  final int unmatchedMoneyCount;

  factory ReportSummary.fromJson(Map<String, dynamic> j) => ReportSummary(
    revenue: (j['revenue'] as num).toInt(),
    expense: (j['expense'] as num).toInt(),
    collected: (j['collected'] as num).toInt(),
    receivable: (j['receivable'] as num).toInt(),
    bankIn: (j['bankIn'] as num).toInt(),
    saleCount: (j['saleCount'] as num?)?.toInt() ?? 0,
    purchaseCount: (j['purchaseCount'] as num?)?.toInt() ?? 0,
    draftCount: (j['draftCount'] as num?)?.toInt() ?? 0,
    unmatchedMoneyCount: (j['unmatchedMoneyCount'] as num?)?.toInt() ?? 0,
  );
}

class ReportDay {
  ReportDay({
    required this.date,
    required this.revenue,
    required this.expense,
    required this.collected,
    required this.bankIn,
    required this.saleCount,
    required this.draftCount,
    required this.unmatchedMoneyCount,
  });

  final String date;
  final int revenue;
  final int expense;
  final int collected;
  final int bankIn;
  final int saleCount;
  final int draftCount;
  final int unmatchedMoneyCount;

  int get openCount => draftCount + unmatchedMoneyCount;

  factory ReportDay.fromJson(Map<String, dynamic> j) => ReportDay(
    date: j['date'] as String,
    revenue: (j['revenue'] as num).toInt(),
    expense: (j['expense'] as num).toInt(),
    collected: (j['collected'] as num).toInt(),
    bankIn: (j['bankIn'] as num).toInt(),
    saleCount: (j['saleCount'] as num?)?.toInt() ?? 0,
    draftCount: (j['draftCount'] as num?)?.toInt() ?? 0,
    unmatchedMoneyCount: (j['unmatchedMoneyCount'] as num?)?.toInt() ?? 0,
  );
}

class ReportType {
  ReportType({required this.type, required this.amount, required this.count});

  final String type; // BusinessEvent.type
  final int amount;
  final int count;

  factory ReportType.fromJson(Map<String, dynamic> j) => ReportType(
    type: j['type'] as String,
    amount: (j['amount'] as num).toInt(),
    count: (j['count'] as num?)?.toInt() ?? 0,
  );
}

class Report {
  Report({
    required this.from,
    required this.to,
    required this.days,
    required this.summary,
    required this.byDay,
    required this.byType,
  });

  final String from;
  final String to;
  final int days;
  final ReportSummary summary;
  final List<ReportDay> byDay;
  final List<ReportType> byType;

  factory Report.fromJson(Map<String, dynamic> j) => Report(
    from: j['from'] as String,
    to: j['to'] as String,
    days: (j['days'] as num).toInt(),
    summary: ReportSummary.fromJson(j['summary'] as Map<String, dynamic>),
    byDay: ((j['byDay'] as List?) ?? const [])
        .map((d) => ReportDay.fromJson(d as Map<String, dynamic>))
        .toList(),
    byType: ((j['byType'] as List?) ?? const [])
        .map((t) => ReportType.fromJson(t as Map<String, dynamic>))
        .toList(),
  );
}
