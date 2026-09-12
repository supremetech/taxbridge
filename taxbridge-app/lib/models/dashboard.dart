class Dashboard {
  Dashboard({
    required this.date,
    required this.revenue,
    required this.expense,
    required this.collected,
    required this.receivable,
    required this.bankIn,
    required this.draftCount,
    required this.unmatchedMoneyCount,
    this.pastDraftCount = 0,
    this.pastUnmatchedCount = 0,
  });

  final String date;
  final int revenue;
  final int expense;
  final int collected;
  final int receivable;
  final int bankIn;
  final int draftCount;
  final int unmatchedMoneyCount;
  final int pastDraftCount; // DRAFT ngày < date (Phase 2 ③)
  final int pastUnmatchedCount; // UNMATCHED ngày < date

  int get pendingCount => pastDraftCount + pastUnmatchedCount;

  factory Dashboard.fromJson(Map<String, dynamic> j) => Dashboard(
    date: j['date'] as String,
    revenue: (j['revenue'] as num).toInt(),
    expense: (j['expense'] as num).toInt(),
    collected: (j['collected'] as num).toInt(),
    receivable: (j['receivable'] as num).toInt(),
    bankIn: (j['bankIn'] as num).toInt(),
    draftCount: (j['draftCount'] as num).toInt(),
    unmatchedMoneyCount: (j['unmatchedMoneyCount'] as num).toInt(),
    pastDraftCount: (j['pastDraftCount'] as num?)?.toInt() ?? 0,
    pastUnmatchedCount: (j['pastUnmatchedCount'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'date': date,
    'revenue': revenue,
    'expense': expense,
    'collected': collected,
    'receivable': receivable,
    'bankIn': bankIn,
    'draftCount': draftCount,
    'unmatchedMoneyCount': unmatchedMoneyCount,
    'pastDraftCount': pastDraftCount,
    'pastUnmatchedCount': pastUnmatchedCount,
  };

  Dashboard copyWith({
    int? bankIn,
    int? unmatchedMoneyCount,
    int? draftCount,
  }) => Dashboard(
    date: date,
    revenue: revenue,
    expense: expense,
    collected: collected,
    receivable: receivable,
    bankIn: bankIn ?? this.bankIn,
    draftCount: draftCount ?? this.draftCount,
    unmatchedMoneyCount: unmatchedMoneyCount ?? this.unmatchedMoneyCount,
    pastDraftCount: pastDraftCount,
    pastUnmatchedCount: pastUnmatchedCount,
  );

  bool sameAs(Dashboard o) =>
      revenue == o.revenue &&
      expense == o.expense &&
      collected == o.collected &&
      receivable == o.receivable &&
      bankIn == o.bankIn &&
      draftCount == o.draftCount &&
      unmatchedMoneyCount == o.unmatchedMoneyCount &&
      pastDraftCount == o.pastDraftCount &&
      pastUnmatchedCount == o.pastUnmatchedCount;
}
