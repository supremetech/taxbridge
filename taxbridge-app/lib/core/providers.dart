import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/session_notifier.dart';
import '../models/business_event.dart';
import '../models/daily_record.dart';
import '../models/dashboard.dart';
import '../models/money_movement.dart';
import '../models/pending.dart';
import '../models/report.dart';
import 'api_client.dart';
import 'config.dart';
import 'dio_taxbridge_api.dart';
import 'fake_taxbridge_api.dart';
import 'format.dart';
import 'taxbridge_api.dart';

final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(
    sessionStore: ref.watch(sessionStoreProvider),
    onUnauthorized: () => ref.read(sessionProvider.notifier).signOut(),
  ),
);

final apiProvider = Provider<TaxBridgeApi>(
  (ref) => useMock
      ? FakeTaxBridgeApi()
      : DioTaxBridgeApi(ref.watch(apiClientProvider)),
);

/// Ngày Home đang xem; mặc định hôm nay. Detail set về ngày của bản ghi trước khi go('/home').
class SelectedDate extends Notifier<String> {
  @override
  String build() => todayKey();
  void set(String d) => state = d;
  void shift(int days) =>
      state = dateKey(DateTime.parse(state).add(Duration(days: days)));
}

final selectedDateProvider = NotifierProvider<SelectedDate, String>(
  SelectedDate.new,
);

final dashboardProvider = FutureProvider.autoDispose<Dashboard>(
  (ref) => ref.watch(apiProvider).dashboard(ref.watch(selectedDateProvider)),
);

final eventsProvider = FutureProvider.autoDispose
    .family<List<BusinessEvent>, String?>(
      (ref, status) => ref.watch(apiProvider).events(status: status),
    );

final eventProvider = FutureProvider.autoDispose.family<BusinessEvent, String>(
  (ref, id) => ref.watch(apiProvider).event(id),
);

final moneyMovementsProvider = FutureProvider.autoDispose
    .family<List<MoneyMovement>, String?>(
      (ref, status) => ref.watch(apiProvider).movements(status: status),
    );

final movementProvider = FutureProvider.autoDispose
    .family<MoneyMovement, String>(
      (ref, id) => ref.watch(apiProvider).movement(id),
    );

final dailyHistoryProvider = FutureProvider.autoDispose<List<DailyRecord>>(
  (ref) => ref.watch(apiProvider).dailyRecords(),
);

final dailyRecordProvider = FutureProvider.autoDispose
    .family<DailyRecord, String>(
      (ref, date) => ref.watch(apiProvider).dailyRecord(date),
    );

final reportProvider = FutureProvider.autoDispose.family<Report, DateRange>(
  (ref, r) => ref.watch(apiProvider).report(r.from, r.to),
);

final pendingProvider = FutureProvider.autoDispose<Pending>(
  (ref) => ref.watch(apiProvider).pending(),
);

/// Dashboard đã render lần trước ở Home — để dựng delta banner + số nhảy (wow 2).
class PrevDashboard extends Notifier<Dashboard?> {
  @override
  Dashboard? build() => null;
  void set(Dashboard? d) => state = d;
}

final prevDashboardProvider = NotifierProvider<PrevDashboard, Dashboard?>(
  PrevDashboard.new,
);

/// Sau mọi mutation: làm mới tất cả dữ liệu đọc một lần.
void invalidateAll(WidgetRef ref) {
  ref.invalidate(dashboardProvider);
  ref.invalidate(eventsProvider);
  ref.invalidate(eventProvider);
  ref.invalidate(moneyMovementsProvider);
  ref.invalidate(movementProvider);
  ref.invalidate(dailyHistoryProvider);
  ref.invalidate(dailyRecordProvider);
  ref.invalidate(reportProvider);
  ref.invalidate(pendingProvider);
}

/// Trước mutation ở Detail (Phase 2 ②): Home sẽ về ngày của bản ghi, nên cần mốc dashboard
/// của **ngày đó** để banner delta so đúng. Home đã có mốc cùng ngày (luồng v1: bản ghi hôm nay,
/// mốc lấy trước capture) → giữ. Khác ngày → đọc `dashboard(d)` rồi trừ phần đóng góp của
/// chính bản ghi ([bankIn] / [unmatched] / [drafts]) để "giả" mốc trước capture → hero
/// `Tiền vào +380.000đ · Doanh thu không đổi ✓` vẫn hiện dù ảnh in 11/09.
Future<void> prepareReturnToDate(
  WidgetRef ref,
  DateTime? occurredAt, {
  int bankIn = 0,
  int unmatched = 0,
  int drafts = 0,
}) async {
  final d = occurredAt == null ? todayKey() : dateKey(occurredAt.toLocal());
  ref.read(selectedDateProvider.notifier).set(d);
  final prev = ref.read(prevDashboardProvider);
  if (prev != null && prev.date == d) return;
  try {
    final base = await ref.read(apiProvider).dashboard(d);
    ref
        .read(prevDashboardProvider.notifier)
        .set(
          base.copyWith(
            bankIn: base.bankIn - bankIn,
            unmatchedMoneyCount: base.unmatchedMoneyCount - unmatched,
            draftCount: base.draftCount - drafts,
          ),
        );
  } catch (_) {
    // không lấy được mốc → Home chỉ không hiện banner
  }
}
