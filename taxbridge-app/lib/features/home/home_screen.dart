import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/widgets.dart';
import '../../models/dashboard.dart';
import '../auth/session_notifier.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  Timer? _poll;
  Timer? _bannerTimer;
  String? _banner;
  Dashboard? _animFrom; // mốc cho số nhảy ở lần render đầu

  @override
  void initState() {
    super.initState();
    _animFrom = ref.read(prevDashboardProvider);
    // Auto-refresh 8 s: UC9 nhắn Zalo từ máy 2 → badge tự nhảy.
    // Chỉ refresh khi Home đang là màn trên cùng, để delta banner so đúng mốc trước capture.
    _poll = Timer.periodic(const Duration(seconds: 8), (_) {
      if (_isCurrent) ref.invalidate(dashboardProvider);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _bannerTimer?.cancel();
    super.dispose();
  }

  bool get _isCurrent => ModalRoute.of(context)?.isCurrent ?? true;

  void _onData(Dashboard d) {
    if (!_isCurrent) return; // đang ở màn khác: giữ mốc cũ, so khi quay về
    final prev = ref.read(prevDashboardProvider);
    if (prev == null || prev.sameAs(d)) {
      if (prev == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) ref.read(prevDashboardProvider.notifier).set(d);
        });
      }
      return;
    }
    final text = dashboardDelta(prev, d);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(prevDashboardProvider.notifier).set(d);
      if (text == null) return;
      setState(() => _banner = text);
      _bannerTimer?.cancel();
      _bannerTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _banner = null);
      });
    });
  }

  /// Lật ngày: không banner delta khi đổi ngày (mốc cũ thuộc ngày khác).
  void _changeDate(void Function(SelectedDate n) fn) {
    ref.read(prevDashboardProvider.notifier).set(null);
    setState(() => _animFrom = null);
    fn(ref.read(selectedDateProvider.notifier));
  }

  Future<void> _logout() async {
    try {
      await ref.read(apiProvider).logout();
    } catch (_) {}
    ref.read(prevDashboardProvider.notifier).set(null);
    ref.read(selectedDateProvider.notifier).set(todayKey());
    await ref.read(sessionProvider.notifier).signOut();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final selected = ref.watch(selectedDateProvider);
    final isToday = selected == todayKey();
    final dash = ref.watch(dashboardProvider);
    // Bỏ qua AsyncLoading (Riverpod giữ value cũ nên hasValue vẫn true) — nếu không
    // mốc prevDashboard bị set bằng dashboard cũ (ngày khác / user khác) → banner sai.
    ref.listen(dashboardProvider, (_, next) {
      if (next.hasValue && !next.isLoading) _onData(next.value!);
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('TaxBridge'),
        actions: [TextButton(onPressed: _logout, child: const Text('Logout'))],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(dashboardProvider.future),
        child: dash.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) =>
              ErrorRetry(onRetry: () => ref.invalidate(dashboardProvider)),
          data: (d) => ListView(
            padding: const EdgeInsets.all(12),
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                layoutBuilder: (current, previous) => Stack(
                  alignment: Alignment.center,
                  children: [
                    ...previous,
                    if (current != null)
                      SizedBox(width: double.infinity, child: current),
                  ],
                ),
                child: _banner == null
                    ? const SizedBox.shrink()
                    : Card(
                        key: ValueKey(_banner),
                        color: Theme.of(context).colorScheme.primaryContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            _banner!,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                      ),
              ),
              Row(
                children: [
                  IconButton(
                    tooltip: 'Ngày trước',
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => _changeDate((n) => n.shift(-1)),
                  ),
                  Expanded(
                    child: Text(
                      displayDateLong(selected),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Ngày sau',
                    icon: const Icon(Icons.chevron_right),
                    onPressed: isToday
                        ? null
                        : () => _changeDate((n) => n.shift(1)),
                  ),
                  if (!isToday)
                    TextButton(
                      onPressed: () => _changeDate((n) => n.set(todayKey())),
                      child: const Text('Hôm nay'),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                child: Text(
                  'Xin chào, ${session?.username ?? ''}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Row(
                children: [
                  _StatCard('Doanh thu', d.revenue, _animFrom?.revenue),
                  _StatCard('Tiền đã thu', d.collected, _animFrom?.collected),
                ],
              ),
              Row(
                children: [
                  _StatCard(
                    'Còn phải thu',
                    d.receivable,
                    _animFrom?.receivable,
                  ),
                  _StatCard('Chi phí', d.expense, _animFrom?.expense),
                ],
              ),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Text('🏦', style: TextStyle(fontSize: 20)),
                      title: const Text('Tiền vào ngân hàng'),
                      trailing: _AnimatedVnd(
                        d.bankIn,
                        _animFrom?.bankIn,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.receipt_long_outlined),
                      title: const Text('Thuế khoán ước tính (1,5% DT)'),
                      trailing: _AnimatedVnd(
                        estTax(d.revenue),
                        _animFrom == null ? null : estTax(_animFrom!.revenue),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _Action(
                    '✍️',
                    'Nhập giao dịch',
                    () => context.push('/capture?mode=text'),
                  ),
                  _Action(
                    '🎤',
                    'Nói giao dịch',
                    () => context.push('/capture?mode=voice'),
                  ),
                ],
              ),
              Row(
                children: [
                  _Action(
                    '📷',
                    'Chụp chứng từ',
                    () => context.push('/capture?mode=receipt'),
                  ),
                  _Action(
                    '💸',
                    'Chụp chuyển khoản',
                    () => context.push('/capture?mode=transfer'),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.all(4),
                child: FilledButton.tonal(
                  onPressed: () => context.push('/capture?mode=history'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('📑 Đối soát lịch sử chuyển khoản'),
                ),
              ),
              const Divider(height: 24),
              if (d.pendingCount > 0)
                Card(
                  color: Theme.of(context).colorScheme.tertiaryContainer,
                  child: ListTile(
                    leading: const Text('⚠', style: TextStyle(fontSize: 20)),
                    title: Text(_pendingText(d)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/pending'),
                  ),
                ),
              Row(
                children: [
                  _Nav(
                    'Giao dịch',
                    d.draftCount,
                    () => context.push('/events'),
                  ),
                  _Nav(
                    'Tiền vào',
                    d.unmatchedMoneyCount,
                    () => context.push('/movements'),
                  ),
                ],
              ),
              Row(
                children: [
                  _Nav('Đóng ngày', 0, () => context.push('/close-day')),
                  _Nav('Lịch sử ngày', 0, () => context.push('/daily-history')),
                ],
              ),
              Row(
                children: [
                  _Nav('Báo cáo', 0, () => context.push('/reports')),
                  _Nav(
                    'Tồn đọng',
                    d.pendingCount,
                    () => context.push('/pending'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

/// `Còn 1 giao dịch · 1 khoản tiền chưa xử lý từ các ngày trước`
String _pendingText(Dashboard d) {
  final parts = [
    if (d.pastDraftCount > 0) 'Còn ${d.pastDraftCount} giao dịch',
    if (d.pastUnmatchedCount > 0)
      '${d.pastDraftCount > 0 ? '' : 'Còn '}${d.pastUnmatchedCount} khoản tiền',
  ];
  return '${parts.join(' · ')} chưa xử lý từ các ngày trước';
}

/// Số tiền chạy 600 ms từ giá trị cũ → mới.
class _AnimatedVnd extends StatelessWidget {
  const _AnimatedVnd(this.value, this.from, {this.style});
  final int value;
  final int? from;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<int>(
    tween: IntTween(begin: from ?? value, end: value),
    duration: const Duration(milliseconds: 600),
    curve: Curves.easeOut,
    builder: (_, v, _) => Text(vnd(v), style: style),
  );
}

class _StatCard extends StatelessWidget {
  const _StatCard(this.label, this.value, this.from);
  final String label;
  final int value;
  final int? from;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            _AnimatedVnd(
              value,
              from,
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Action extends StatelessWidget {
  const _Action(this.emoji, this.label, this.onTap);
  final String emoji;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Padding(
      padding: const EdgeInsets.all(4),
      child: FilledButton.tonal(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: Text('$emoji $label', textAlign: TextAlign.center),
      ),
    ),
  );
}

class _Nav extends StatelessWidget {
  const _Nav(this.label, this.badge, this.onTap);
  final String label;
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Padding(
      padding: const EdgeInsets.all(4),
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label),
            if (badge > 0) ...[
              const SizedBox(width: 6),
              Badge.count(count: badge),
            ],
          ],
        ),
      ),
    ),
  );
}

/// So dashboard mới với bản đã render lần trước → text delta banner (wow 2).
/// Ví dụ: `Tiền vào +380.000đ · Doanh thu không đổi ✓`; null khi không có gì đáng nói.
String? dashboardDelta(Dashboard prev, Dashboard d) {
  final parts = <String>[];
  void add(String label, int from, int to) {
    if (from != to) parts.add('$label ${vndDelta(to - from)}');
  }

  add('Doanh thu', prev.revenue, d.revenue);
  add('Tiền đã thu', prev.collected, d.collected);
  add('Còn phải thu', prev.receivable, d.receivable);
  add('Chi phí', prev.expense, d.expense);
  add('Tiền vào', prev.bankIn, d.bankIn);

  final revenueSame = prev.revenue == d.revenue;
  final moneyMoved =
      prev.bankIn != d.bankIn ||
      d.unmatchedMoneyCount < prev.unmatchedMoneyCount;
  if (revenueSame && moneyMoved) parts.add('Doanh thu không đổi ✓');
  return parts.isEmpty ? null : parts.join(' · ');
}
