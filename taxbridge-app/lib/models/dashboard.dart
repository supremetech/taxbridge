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
  });

  final String date;
  final int revenue;
  final int expense;
  final int collected;
  final int receivable;
  final int bankIn;
  final int draftCount;
  final int unmatchedMoneyCount;

  factory Dashboard.fromJson(Map<String, dynamic> j) => Dashboard(
    date: j['date'] as String,
    revenue: (j['revenue'] as num).toInt(),
    expense: (j['expense'] as num).toInt(),
    collected: (j['collected'] as num).toInt(),
    receivable: (j['receivable'] as num).toInt(),
    bankIn: (j['bankIn'] as num).toInt(),
    draftCount: (j['draftCount'] as num).toInt(),
    unmatchedMoneyCount: (j['unmatchedMoneyCount'] as num).toInt(),
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
  };

  bool sameAs(Dashboard o) =>
      revenue == o.revenue &&
      expense == o.expense &&
      collected == o.collected &&
      receivable == o.receivable &&
      bankIn == o.bankIn &&
      draftCount == o.draftCount &&
      unmatchedMoneyCount == o.unmatchedMoneyCount;
}
