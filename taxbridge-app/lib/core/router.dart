import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/login_screen.dart';
import '../features/auth/register_screen.dart';
import '../features/auth/session_notifier.dart';
import '../features/capture/capture_screen.dart';
import '../features/close_day/close_day_screen.dart';
import '../features/close_day/daily_history_screen.dart';
import '../features/close_day/daily_record_detail_screen.dart';
import '../features/events/event_detail_screen.dart';
import '../features/events/event_list_screen.dart';
import '../features/home/home_screen.dart';
import '../features/movements/movement_detail_screen.dart';
import '../features/movements/movement_list_screen.dart';
import '../features/movements/reconcile_screen.dart';
import '../features/pending/pending_screen.dart';
import '../features/reports/report_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  // Đổi session → GoRouter chạy lại redirect.
  final refresh = ValueNotifier(0);
  ref.listen(sessionProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/home',
    refreshListenable: refresh,
    redirect: (context, state) {
      final loggedIn = ref.read(sessionProvider) != null;
      final path = state.uri.path;
      final onAuth = path == '/login' || path == '/register';
      if (!loggedIn && !onAuth) return '/login';
      if (loggedIn && onAuth) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, _) => const RegisterScreen()),
      GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
      GoRoute(
        path: '/capture',
        builder: (_, s) =>
            CaptureScreen(mode: s.uri.queryParameters['mode'] ?? 'text'),
      ),
      GoRoute(path: '/events', builder: (_, _) => const EventListScreen()),
      GoRoute(
        path: '/events/:id',
        builder: (_, s) => EventDetailScreen(id: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/movements',
        builder: (_, _) => const MovementListScreen(),
      ),
      GoRoute(
        path: '/movements/:id',
        builder: (_, s) => MovementDetailScreen(id: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/reconcile',
        builder: (_, s) => ReconcileScreen(
          ids: (s.uri.queryParameters['ids'] ?? '')
              .split(',')
              .where((x) => x.isNotEmpty)
              .toList(),
          skipped: int.tryParse(s.uri.queryParameters['skipped'] ?? '') ?? 0,
        ),
      ),
      GoRoute(path: '/reports', builder: (_, _) => const ReportScreen()),
      GoRoute(path: '/pending', builder: (_, _) => const PendingScreen()),
      GoRoute(path: '/close-day', builder: (_, _) => const CloseDayScreen()),
      GoRoute(
        path: '/daily-history',
        builder: (_, _) => const DailyHistoryScreen(),
      ),
      GoRoute(
        path: '/daily-history/:date',
        builder: (_, s) =>
            DailyRecordDetailScreen(date: s.pathParameters['date']!),
      ),
    ],
  );
});
