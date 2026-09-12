import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session_store.dart';
import '../../models/session.dart';

/// Session đã load ở app start (override trong `main.dart`).
final initialSessionProvider = Provider<AppSession?>((_) => null);
final sessionStoreProvider = Provider<SessionStore>((_) => SessionStore());

class SessionNotifier extends Notifier<AppSession?> {
  @override
  AppSession? build() => ref.watch(initialSessionProvider);

  Future<void> signIn(AppSession s) async {
    await ref.read(sessionStoreProvider).save(s);
    state = s;
  }

  Future<void> signOut() async {
    await ref.read(sessionStoreProvider).clear();
    state = null;
  }
}

final sessionProvider = NotifierProvider<SessionNotifier, AppSession?>(
  SessionNotifier.new,
);
