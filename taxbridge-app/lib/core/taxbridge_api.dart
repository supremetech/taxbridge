import '../models/business_event.dart';
import '../models/capture_result.dart';
import '../models/daily_record.dart';
import '../models/dashboard.dart';
import '../models/money_movement.dart';
import '../models/session.dart';
import '../models/zalo_user.dart';

/// Hợp đồng REST của TaxBridge (xem `contract/endpoints.md`).
abstract class TaxBridgeApi {
  Future<void> health();
  Future<List<ZaloUser>> unlinkedZaloUsers();
  Future<AppSession> register(String username, String password, String? zaloId);
  Future<AppSession> login(String username, String password);
  Future<void> logout();
  Future<CaptureResult> captureText(String text);

  /// [type]: AUDIO | IMAGE_RECEIPT | IMAGE_TRANSFER
  Future<CaptureResult> captureFile(String type, String path);
  Future<List<BusinessEvent>> events({String? status});
  Future<BusinessEvent> event(String id);
  Future<BusinessEvent> updateEvent(String id, Map<String, dynamic> patch);
  Future<BusinessEvent> confirmEvent(String id);
  Future<BusinessEvent> rejectEvent(String id);
  Future<List<MoneyMovement>> movements({String? status});
  Future<MoneyMovement> movement(String id);
  Future<MoneyMovement> matchMovement(String id, String eventId);
  Future<MoneyMovement> classifyMovement(String id, String type);
  Future<Dashboard> dashboard(String date);
  Future<DailyRecord> closeDay(String date);
  Future<List<DailyRecord>> dailyRecords();
  Future<DailyRecord> dailyRecord(String date);
}
