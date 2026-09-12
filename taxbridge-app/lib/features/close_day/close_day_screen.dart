import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/widgets.dart';
import '../../models/daily_record.dart';
import 'warning_tile.dart';

class CloseDayScreen extends ConsumerStatefulWidget {
  const CloseDayScreen({super.key});

  @override
  ConsumerState<CloseDayScreen> createState() => _CloseDayScreenState();
}

class _CloseDayScreenState extends ConsumerState<CloseDayScreen> {
  DailyRecord? _record;
  bool _busy = false;

  Future<void> _close() async {
    setState(() => _busy = true);
    try {
      final r = await ref
          .read(apiProvider)
          .closeDay(ref.read(selectedDateProvider));
      ref.invalidate(dailyHistoryProvider);
      ref.invalidate(dailyRecordProvider);
      if (mounted) setState(() => _record = r);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _record;
    final date = ref.watch(selectedDateProvider);
    return Scaffold(
      appBar: AppBar(title: Text('Đóng ngày ${displayDate(date)}')),
      body: BusyOverlay(
        busy: _busy,
        text: 'Đang tổng kết…',
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (r == null) ...[
              const SizedBox(height: 40),
              Icon(
                Icons.nightlight_round,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              const Text(
                'Tổng kết doanh thu, chi phí và những khoản còn dang dở của ngày đang xem.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _close,
                child: const Text('Đóng ngày'),
              ),
            ] else ...[
              SummaryGrid(
                revenue: r.summary.revenue,
                collected: r.summary.collected,
                receivable: r.summary.receivable,
                expense: r.summary.expense,
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  r.openCount == 0
                      ? 'Không có cảnh báo. Ngày sạch ✓'
                      : 'Cảnh báo cần xử lý (${r.openCount})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              for (final w in r.warnings.where((w) => w.isOpen)) WarningTile(w),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => context.push('/daily-history'),
                child: const Text('Xem lịch sử ngày'),
              ),
              TextButton(
                onPressed: _busy ? null : _close,
                child: const Text('Đóng lại ngày'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
