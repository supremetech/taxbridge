class CaptureResult {
  CaptureResult({
    required this.captureId,
    required this.status,
    this.resultType,
    this.resultId,
    this.resultIds = const [],
    this.skippedCount = 0,
    this.occurredAt,
    this.error,
  });

  final String captureId;
  final String status; // PROCESSING | DONE | FAILED
  final String? resultType; // EVENT | MONEY_MOVEMENT | MONEY_MOVEMENT_BATCH
  final String? resultId;
  final List<String> resultIds; // batch (IMAGE_BANK_HISTORY)
  final int skippedCount; // dòng trùng đã bỏ (batch)
  final DateTime? occurredAt; // ngày trên chứng từ (Phase 2 ②)
  final String? error;

  bool get isBatch => resultType == 'MONEY_MOVEMENT_BATCH';
  bool get isDone => status == 'DONE' && (resultId != null || isBatch);

  factory CaptureResult.fromJson(Map<String, dynamic> j) => CaptureResult(
    captureId: j['captureId'] as String,
    status: j['status'] as String,
    resultType: j['resultType'] as String?,
    resultId: j['resultId'] as String?,
    resultIds: ((j['resultIds'] as List?) ?? const []).cast<String>(),
    skippedCount: (j['skippedCount'] as num?)?.toInt() ?? 0,
    occurredAt: DateTime.tryParse(j['occurredAt'] as String? ?? ''),
    error: j['error'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'captureId': captureId,
    'status': status,
    'resultType': resultType,
    'resultId': resultId,
    'resultIds': resultIds,
    'skippedCount': skippedCount,
    'occurredAt': occurredAt?.toIso8601String(),
    'error': error,
  };
}
