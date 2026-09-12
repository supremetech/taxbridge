import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/session_notifier.dart';
import '../models/business_event.dart';
import '../models/daily_record.dart';
import '../models/dashboard.dart';
import '../models/money_movement.dart';
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

final dashboardProvider = FutureProvider.autoDispose<Dashboard>(
  (ref) => ref.watch(apiProvider).dashboard(todayKey()),
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
}
