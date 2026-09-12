class MatchCandidate {
  MatchCandidate({
    required this.eventId,
    required this.description,
    required this.amount,
    required this.score,
  });

  final String eventId;
  final String description;
  final int amount;
  final double score;

  factory MatchCandidate.fromJson(Map<String, dynamic> j) => MatchCandidate(
    eventId: j['eventId'] as String,
    description: j['description'] as String? ?? '',
    amount: (j['amount'] as num).toInt(),
    score: (j['score'] as num?)?.toDouble() ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'eventId': eventId,
    'description': description,
    'amount': amount,
    'score': score,
  };
}

class MoneyMovement {
  MoneyMovement({
    required this.movementId,
    required this.direction,
    required this.amount,
    this.memo,
    this.counterparty,
    this.occurredAt,
    required this.source,
    required this.captureType,
    this.evidenceText,
    this.evidenceUrl,
    required this.status,
    this.matchedEventId,
    this.classificationType,
    required this.candidates,
  });

  final String movementId;
  final String direction; // IN | OUT
  final int amount;
  final String? memo;
  final String? counterparty;
  final DateTime? occurredAt;
  final String source;
  final String captureType;
  final String? evidenceText;
  final String? evidenceUrl;
  final String status; // UNMATCHED | MATCHED | CLASSIFIED
  final String? matchedEventId;
  final String? classificationType; // DEPOSIT | OWNER_MONEY | OTHER | UNKNOWN
  final List<MatchCandidate> candidates;

  bool get isUnmatched => status == 'UNMATCHED';

  factory MoneyMovement.fromJson(Map<String, dynamic> j) => MoneyMovement(
    movementId: j['movementId'] as String,
    direction: j['direction'] as String? ?? 'IN',
    amount: (j['amount'] as num).toInt(),
    memo: j['memo'] as String?,
    counterparty: j['counterparty'] as String?,
    occurredAt: DateTime.tryParse(j['occurredAt'] as String? ?? ''),
    source: j['source'] as String? ?? 'APP',
    captureType: j['captureType'] as String? ?? 'IMAGE_TRANSFER',
    evidenceText: j['evidenceText'] as String?,
    evidenceUrl: j['evidenceUrl'] as String?,
    status: j['status'] as String,
    matchedEventId: j['matchedEventId'] as String?,
    classificationType: j['classificationType'] as String?,
    candidates: ((j['candidates'] as List?) ?? const [])
        .map((c) => MatchCandidate.fromJson(c as Map<String, dynamic>))
        .toList(),
  );

  Map<String, dynamic> toJson() => {
    'movementId': movementId,
    'direction': direction,
    'amount': amount,
    'memo': memo,
    'counterparty': counterparty,
    'occurredAt': occurredAt?.toIso8601String(),
    'source': source,
    'captureType': captureType,
    'evidenceText': evidenceText,
    'evidenceUrl': evidenceUrl,
    'status': status,
    'matchedEventId': matchedEventId,
    'classificationType': classificationType,
    'candidates': candidates.map((c) => c.toJson()).toList(),
  };
}
