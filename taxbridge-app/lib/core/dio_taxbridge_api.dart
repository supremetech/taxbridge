import 'package:dio/dio.dart';

import '../models/business_event.dart';
import '../models/capture_result.dart';
import '../models/daily_record.dart';
import '../models/dashboard.dart';
import '../models/money_movement.dart';
import '../models/pending.dart';
import '../models/report.dart';
import '../models/session.dart';
import '../models/zalo_user.dart';
import 'api_client.dart';
import 'taxbridge_api.dart';

class DioTaxBridgeApi implements TaxBridgeApi {
  DioTaxBridgeApi(this.client);
  final ApiClient client;
  Dio get _dio => client.dio;

  /// Gói DioException thành ApiException để widget đọc `code`.
  Future<T> _call<T>(
    Future<Response<dynamic>> Function() fn,
    T Function(dynamic data) parse,
  ) async {
    try {
      final r = await fn();
      return parse(r.data);
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }

  Map<String, dynamic> _map(dynamic d) => d as Map<String, dynamic>;
  List<Map<String, dynamic>> _list(dynamic d) =>
      (d as List).cast<Map<String, dynamic>>();

  @override
  Future<void> health() => _call(() => _dio.get('/api/health'), (_) {});

  @override
  Future<List<ZaloUser>> unlinkedZaloUsers() => _call(
    () => _dio.get('/api/zalo-users/unlinked'),
    (d) => _list(d).map(ZaloUser.fromJson).toList(),
  );

  @override
  Future<AppSession> register(
    String username,
    String password,
    String? zaloId,
  ) => _call(
    () => _dio.post(
      '/api/register',
      data: {'username': username, 'password': password, 'zaloId': ?zaloId},
    ),
    (d) => AppSession.fromJson(_map(d)),
  );

  @override
  Future<AppSession> login(String username, String password) => _call(
    () => _dio.post(
      '/api/login',
      data: {'username': username, 'password': password},
    ),
    (d) => AppSession.fromJson(_map(d)),
  );

  @override
  Future<void> logout() => _call(() => _dio.post('/api/logout'), (_) {});

  @override
  Future<CaptureResult> captureText(String text) => _call(
    () => _dio.post('/api/captures', data: {'type': 'TEXT', 'text': text}),
    (d) => CaptureResult.fromJson(_map(d)),
  );

  @override
  Future<CaptureResult> captureFile(String type, String path) async {
    final ext = path.split('.').last.toLowerCase();
    final mime = switch (ext) {
      'png' => DioMediaType('image', 'png'),
      'm4a' => DioMediaType('audio', 'mp4'),
      _ => DioMediaType('image', 'jpeg'),
    };
    final form = FormData.fromMap({
      'type': type,
      'file': await MultipartFile.fromFile(
        path,
        filename: path.split('/').last,
        contentType: mime,
      ),
    });
    return _call(
      () => _dio.post('/api/captures', data: form),
      (d) => CaptureResult.fromJson(_map(d)),
    );
  }

  @override
  Future<List<BusinessEvent>> events({String? status}) => _call(
    () => _dio.get('/api/events', queryParameters: {'status': ?status}),
    (d) => _list(d).map(BusinessEvent.fromJson).toList(),
  );

  @override
  Future<BusinessEvent> event(String id) => _call(
    () => _dio.get('/api/events/$id'),
    (d) => BusinessEvent.fromJson(_map(d)),
  );

  @override
  Future<BusinessEvent> updateEvent(String id, Map<String, dynamic> patch) =>
      _call(
        () => _dio.put('/api/events/$id', data: patch),
        (d) => BusinessEvent.fromJson(_map(d)),
      );

  @override
  Future<BusinessEvent> confirmEvent(String id) => _call(
    () => _dio.post('/api/events/$id/confirm'),
    (d) => BusinessEvent.fromJson(_map(d)),
  );

  @override
  Future<BusinessEvent> rejectEvent(String id) => _call(
    () => _dio.post('/api/events/$id/reject'),
    (d) => BusinessEvent.fromJson(_map(d)),
  );

  @override
  Future<List<MoneyMovement>> movements({String? status}) => _call(
    () =>
        _dio.get('/api/money-movements', queryParameters: {'status': ?status}),
    (d) => _list(d).map(MoneyMovement.fromJson).toList(),
  );

  @override
  Future<MoneyMovement> movement(String id) => _call(
    () => _dio.get('/api/money-movements/$id'),
    (d) => MoneyMovement.fromJson(_map(d)),
  );

  @override
  Future<MoneyMovement> matchMovement(String id, String eventId) => _call(
    () =>
        _dio.post('/api/money-movements/$id/match', data: {'eventId': eventId}),
    (d) => MoneyMovement.fromJson(_map(d)),
  );

  @override
  Future<MoneyMovement> classifyMovement(String id, String type) => _call(
    () => _dio.post('/api/money-movements/$id/classify', data: {'type': type}),
    (d) => MoneyMovement.fromJson(_map(d)),
  );

  @override
  Future<Dashboard> dashboard(String date) => _call(
    () => _dio.get('/api/dashboard', queryParameters: {'date': date}),
    (d) => Dashboard.fromJson(_map(d)),
  );

  @override
  Future<DailyRecord> closeDay(String date) => _call(
    () => _dio.post('/api/close-day', data: {'date': date}),
    (d) => DailyRecord.fromJson(_map(d)),
  );

  @override
  Future<List<DailyRecord>> dailyRecords() => _call(
    () => _dio.get('/api/daily-records'),
    (d) => _list(d).map(DailyRecord.fromJson).toList(),
  );

  @override
  Future<DailyRecord> dailyRecord(String date) => _call(
    () => _dio.get('/api/daily-records/$date'),
    (d) => DailyRecord.fromJson(_map(d)),
  );

  // ---- Phase 2 ----

  @override
  Future<Report> report(String from, String to) => _call(
    () => _dio.get('/api/reports', queryParameters: {'from': from, 'to': to}),
    (d) => Report.fromJson(_map(d)),
  );

  @override
  Future<Pending> pending() =>
      _call(() => _dio.get('/api/pending'), (d) => Pending.fromJson(_map(d)));

  @override
  Future<ReplayResult> replayZalo(String zaloId) => _call(
    () => _dio.post('/api/zalo-users/$zaloId/replay'),
    (d) => ReplayResult.fromJson(_map(d)),
  );
}
