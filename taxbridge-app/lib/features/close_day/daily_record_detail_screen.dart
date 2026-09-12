import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/widgets.dart';
import 'warning_tile.dart';

class DailyRecordDetailScreen extends ConsumerStatefulWidget {
  const DailyRecordDetailScreen({super.key, required this.date});
  final String date;

  @override
  ConsumerState<DailyRecordDetailScreen> createState() =>
      _DailyRecordDetailScreenState();
}

class _DailyRecordDetailScreenState
    extends ConsumerState<DailyRecordDetailScreen> {
  bool _showResolved = false;

  @override
  Widget build(BuildContext context) {
    final rec = ref.watch(dailyRecordProvider(widget.date));
    return Scaffold(
      appBar: AppBar(title: Text('Ngày ${displayDate(widget.date)}')),
      body: rec.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorRetry(
          onRetry: () => ref.invalidate(dailyRecordProvider(widget.date)),
        ),
        data: (r) {
          final shown = r.warnings
              .where((w) => _showResolved || w.isOpen)
              .toList();
          return RefreshIndicator(
            onRefresh: () =>
                ref.refresh(dailyRecordProvider(widget.date).future),
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                SummaryGrid(
                  revenue: r.summary.revenue,
                  collected: r.summary.collected,
                  receivable: r.summary.receivable,
                  expense: r.summary.expense,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Cảnh báo (${r.openCount} mở)',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    const Text('Xem đã xử lý'),
                    Switch(
                      value: _showResolved,
                      onChanged: (v) => setState(() => _showResolved = v),
                    ),
                  ],
                ),
                if (shown.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('Không có cảnh báo ✓')),
                  ),
                for (final w in shown) WarningTile(w),
                if (r.closedAt != null)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      'Đóng lúc ${displayTime(r.closedAt)} · cập nhật ${displayTime(r.updatedAt)}',
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
