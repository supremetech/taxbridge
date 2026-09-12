import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/providers.dart';
import 'core/session_store.dart';
import 'features/auth/session_notifier.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Để tool Simulator (accessibility inspect) đọc được nhãn nút / ô nhập.
  SemanticsBinding.instance.ensureSemantics();

  final store = SessionStore();
  final session = await store.load();

  final container = ProviderContainer(
    overrides: [
      sessionStoreProvider.overrideWithValue(store),
      initialSessionProvider.overrideWithValue(session),
    ],
  );
  // Warm function; bỏ qua lỗi.
  container.read(apiProvider).health().catchError((_) {});

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const TaxBridgeApp(),
    ),
  );
}
