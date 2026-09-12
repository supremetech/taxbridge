import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/widgets.dart';
import '../../models/report.dart';
import '../events/event_list_screen.dart' show eventTypeLabel;

/// Báo cáo theo khoảng ngày (Phase 2 ④, plan FE §11).
class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({super.key});

  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  String _preset = '7 ngày';
  DateRange _range = rangeLast7();

  static final _presets = <String, DateRange Function()>{
    'Hôm nay': rangeToday,
    '7 ngày': rangeLast7,
    'Tháng này': rangeThisMonth,
    'Tháng trước': rangeLastMonth,
  };

  Future<void> _pickCustom() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1, now.month, now.day),
      lastDate: now,
      initialDateRange: DateTimeRange(
        start: DateTime.parse(_range.from),
        end: DateTime.parse(_range.to),
      ),
      saveText: 'Lưu',
    );
    if (r == null) return;
    setState(() {
      _preset = 'Tùy chọn';
      _range = (from: dateKey(r.start), to: dateKey(r.end));
    });
  }

  @override
  Widget build(BuildContext context) {
    final rep = ref.watch(reportProvider(_range));
    return Scaffold(
      appBar: AppBar(title: const Text('Báo cáo')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(reportProvider(_range).future),
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final p in _presets.entries) ...[
                    ChoiceChip(
                      label: Text(p.key),
                      selected: _preset == p.key,
                      onSelected: (_) => setState(() {
                        _preset = p.key;
                        _range = p.value();
                      }),
                    ),
                    const SizedBox(width: 6),
                  ],
                  ChoiceChip(
                    label: const Text('Tùy chọn'),
                    selected: _preset == 'Tùy chọn',
                    onSelected: (_) => _pickCustom(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            rep.when(
              loading: () => const Padding(
                padding: EdgeInsets.only(top: 80),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => ErrorRetry(
                onRetry: () => ref.invalidate(reportProvider(_range)),
              ),
              data: (r) => _ReportBody(r),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportBody extends ConsumerWidget {
  const _ReportBody(this.r);
  final Report r;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final s = r.summary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Text(
            displayRange((from: r.from, to: r.to), r.days),
            style: theme.textTheme.titleSmall,
          ),
        ),
        SummaryGrid(
          revenue: s.revenue,
          collected: s.collected,
          receivable: s.receivable,
          expense: s.expense,
          bankIn: s.bankIn,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            '${s.saleCount} đơn bán · ${s.purchaseCount} mua · '
            '${s.draftCount} nháp · ${s.unmatchedMoneyCount} tiền vào chưa xử lý',
            style: theme.textTheme.bodySmall,
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text('Theo ngày', style: theme.textTheme.titleMedium),
        ),
        if (r.byDay.isEmpty)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('Không có dữ liệu trong khoảng này.'),
          ),
        for (final d in r.byDay)
          Card(
            child: ListTile(
              title: Text(displayDate(d.date)),
              subtitle: Text('DT ${vnd(d.revenue)} · CP ${vnd(d.expense)}'),
              trailing: d.openCount > 0
                  ? Badge.count(
                      count: d.openCount,
                      backgroundColor: theme.colorScheme.tertiary,
                    )
                  : const Icon(Icons.chevron_right),
              onTap: () {
                // Drill: Home của ngày đó (không banner).
                ref.read(prevDashboardProvider.notifier).set(null);
                ref.read(selectedDateProvider.notifier).set(d.date);
                context.go('/home');
              },
            ),
          ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text('Theo loại', style: theme.textTheme.titleMedium),
        ),
        for (final t in r.byType)
          ListTile(
            dense: true,
            title: Text(eventTypeLabel(t.type)),
            trailing: Text(
              '${vnd(t.amount)} (${t.count})',
              style: theme.textTheme.bodyLarge,
            ),
          ),
        const SizedBox(height: 24),
      ],
    );
  }
}
