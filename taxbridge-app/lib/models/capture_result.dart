class CaptureResult {
  CaptureResult({
    required this.captureId,
    required this.status,
    this.resultType,
    this.resultId,
    this.error,
  });

  final String captureId;
  final String status; // PROCESSING | DONE | FAILED
  final String? resultType; // EVENT | MONEY_MOVEMENT
  final String? resultId;
  final String? error;

  bool get isDone => status == 'DONE' && resultId != null;

  factory CaptureResult.fromJson(Map<String, dynamic> j) => CaptureResult(
    captureId: j['captureId'] as String,
    status: j['status'] as String,
    resultType: j['resultType'] as String?,
    resultId: j['resultId'] as String?,
    error: j['error'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'captureId': captureId,
    'status': status,
    'resultType': resultType,
    'resultId': resultId,
    'error': error,
  };
}
