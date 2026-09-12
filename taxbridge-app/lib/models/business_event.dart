class BusinessEvent {
  BusinessEvent({
    required this.eventId,
    required this.type,
    required this.status,
    required this.amount,
    this.description,
    this.counterparty,
    this.paymentMethod,
    this.paymentStatus,
    this.occurredAt,
    required this.source,
    required this.captureType,
    this.evidenceText,
    this.evidenceUrl,
    this.confidence,
  });

  final String eventId;
  final String type; // SALE | PURCHASE | DEPOSIT | OWNER_MONEY | UNKNOWN
  final String status; // DRAFT | CONFIRMED | REJECTED
  final int amount;
  final String? description;
  final String? counterparty;
  final String? paymentMethod; // CASH | BANK | UNKNOWN
  final String? paymentStatus; // UNPAID | PAID | UNKNOWN
  final DateTime? occurredAt;
  final String source; // APP | ZALO
  final String captureType; // TEXT | AUDIO | IMAGE_RECEIPT | IMAGE_TRANSFER
  final String? evidenceText;
  final String? evidenceUrl;
  final double? confidence;

  bool get isDraft => status == 'DRAFT';

  factory BusinessEvent.fromJson(Map<String, dynamic> j) => BusinessEvent(
    eventId: j['eventId'] as String,
    type: j['type'] as String,
    status: j['status'] as String,
    amount: (j['amount'] as num).toInt(),
    description: j['description'] as String?,
    counterparty: j['counterparty'] as String?,
    paymentMethod: j['paymentMethod'] as String?,
    paymentStatus: j['paymentStatus'] as String?,
    occurredAt: DateTime.tryParse(j['occurredAt'] as String? ?? ''),
    source: j['source'] as String? ?? 'APP',
    captureType: j['captureType'] as String? ?? 'TEXT',
    evidenceText: j['evidenceText'] as String?,
    evidenceUrl: j['evidenceUrl'] as String?,
    confidence: (j['confidence'] as num?)?.toDouble(),
  );

  Map<String, dynamic> toJson() => {
    'eventId': eventId,
    'type': type,
    'status': status,
    'amount': amount,
    'description': description,
    'counterparty': counterparty,
    'paymentMethod': paymentMethod,
    'paymentStatus': paymentStatus,
    'occurredAt': occurredAt?.toIso8601String(),
    'source': source,
    'captureType': captureType,
    'evidenceText': evidenceText,
    'evidenceUrl': evidenceUrl,
    'confidence': confidence,
  };
}
