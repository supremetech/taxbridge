import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router.dart';

class TaxBridgeApp extends ConsumerWidget {
  const TaxBridgeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'TaxBridge',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF0B6E4F),
        useMaterial3: true,
        cardTheme: const CardThemeData(margin: EdgeInsets.all(4)),
      ),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
