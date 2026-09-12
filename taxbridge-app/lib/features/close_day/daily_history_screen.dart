import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/widgets.dart';

class DailyHistoryScreen extends ConsumerWidget {
  const DailyHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(dailyHistoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Lịch sử ngày')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(dailyHistoryProvider.future),
        child: list.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) =>
              ErrorRetry(onRetry: () => ref.invalidate(dailyHistoryProvider)),
          data: (records) => records.isEmpty
              ? ListView(
                  children: const [
                    SizedBox(height: 120),
                    Center(child: Text('Chưa đóng ngày nào')),
                  ],
                )
              : ListView.builder(
                  itemCount: records.length,
                  itemBuilder: (_, i) {
                    final r = records[i];
                    final n = r.openCount;
                    return Card(
                      child: ListTile(
                        onTap: () => context.push('/daily-history/${r.date}'),
                        title: Text(
                          '${displayDate(r.date)} · Doanh thu ${vnd(r.summary.revenue)}',
                        ),
                        subtitle: Text('Chi phí ${vnd(r.summary.expense)}'),
                        trailing: Text(
                          n == 0 ? '✓' : '⚠ $n',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: n == 0
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).colorScheme.tertiary,
                              ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}
