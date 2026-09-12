import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/widgets.dart';
import '../../models/pending.dart';
import '../events/event_list_screen.dart' show EventCard;
import '../movements/movement_list_screen.dart' show MovementCard;

/// Tồn đọng mọi ngày, gom theo ngày cũ nhất trước (Phase 2 ③, plan FE §12).
class PendingScreen extends ConsumerWidget {
  const PendingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(pendingProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Tồn đọng')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(pendingProvider.future),
        child: p.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) =>
              ErrorRetry(onRetry: () => ref.invalidate(pendingProvider)),
          data: (p) => p.isEmpty
              ? ListView(
                  children: const [
                    SizedBox(height: 120),
                    Center(child: Text('✓ Không còn giao dịch tồn đọng')),
                  ],
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [for (final d in p.byDate) ..._day(context, p, d)],
                ),
        ),
      ),
    );
  }

  List<Widget> _day(BuildContext context, Pending p, PendingDay d) {
    String day(DateTime? t) => t == null ? '' : dateKey(t.toLocal());
    final header = [
      displayDate(d.date),
      if (d.draftCount > 0) '${d.draftCount} nháp',
      if (d.unmatchedCount > 0) '${d.unmatchedCount} tiền vào',
    ].join(' · ');
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(header, style: Theme.of(context).textTheme.titleMedium),
      ),
      for (final e in p.draftEvents.where((e) => day(e.occurredAt) == d.date))
        EventCard(e),
      for (final m in p.unmatchedMovements.where(
        (m) => day(m.occurredAt) == d.date,
      ))
        MovementCard(m),
    ];
  }
}
