import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/widgets.dart';
import '../../models/money_movement.dart';

/// Đối soát batch lịch sử CK (Phase 2 ①, plan FE §13): mỗi dòng = movementProvider(id).
class ReconcileScreen extends ConsumerStatefulWidget {
  const ReconcileScreen({super.key, required this.ids, required this.skipped});
  final List<String> ids;
  final int skipped;

  @override
  ConsumerState<ReconcileScreen> createState() => _ReconcileScreenState();
}

class _ReconcileScreenState extends ConsumerState<ReconcileScreen> {
  String? _busyId;

  Future<void> _run(String id, Future<MoneyMovement> Function() fn) async {
    setState(() => _busyId = id);
    try {
      await fn();
      ref.invalidate(movementProvider(id));
      ref.invalidate(dashboardProvider);
      ref.invalidate(moneyMovementsProvider);
      ref.invalidate(pendingProvider);
    } catch (e) {
      if (!mounted) return;
      showError(context, e);
      ref.invalidate(movementProvider(id));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  void _match(MoneyMovement m) => _run(
    m.movementId,
    () => ref
        .read(apiProvider)
        .matchMovement(m.movementId, m.candidates.first.eventId),
  );

  Future<void> _classify(MoneyMovement m) async {
    final type = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                '${vnd(m.amount)} · ${m.memo ?? ''} — khoản này là gì?',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            for (final (t, label) in const [
              ('DEPOSIT', 'Đặt cọc'),
              ('OWNER_MONEY', 'Tiền cá nhân'),
              ('OTHER', 'Khác'),
              ('UNKNOWN', 'Không rõ'),
            ])
              ListTile(title: Text(label), onTap: () => Navigator.pop(ctx, t)),
          ],
        ),
      ),
    );
    if (type == null) return;
    await _run(
      m.movementId,
      () => ref.read(apiProvider).classifyMovement(m.movementId, type),
    );
  }

  /// Xong → Home của ngày mới nhất trong batch (theo movement đã tải).
  void _done() {
    String? latest;
    for (final id in widget.ids) {
      final at = ref.read(movementProvider(id)).value?.occurredAt;
      if (at == null) continue;
      final d = dateKey(at.toLocal());
      if (latest == null || d.compareTo(latest) > 0) latest = d;
    }
    ref.read(prevDashboardProvider.notifier).set(null);
    ref.read(selectedDateProvider.notifier).set(latest ?? todayKey());
    invalidateAll(ref);
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Đối soát ${widget.ids.length} giao dịch mới'),
            if (widget.skipped > 0)
              Text(
                '(${widget.skipped} dòng đã có)',
                style: theme.textTheme.bodySmall,
              ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          for (final id in widget.ids) _Row(id: id, state: this),
          const SizedBox(height: 16),
          FilledButton(onPressed: _done, child: const Text('Xong')),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _Row extends ConsumerWidget {
  const _Row({required this.id, required this.state});
  final String id;
  final _ReconcileScreenState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final mv = ref.watch(movementProvider(id));
    return Card(
      child: mv.when(
        loading: () => const ListTile(title: LinearProgressIndicator()),
        error: (e, _) => ListTile(
          title: const Text('Không tải được'),
          trailing: TextButton(
            onPressed: () => ref.invalidate(movementProvider(id)),
            child: const Text('Thử lại'),
          ),
        ),
        data: (m) {
          final busy = state._busyId == id;
          final out = m.direction == 'OUT';
          final cand = m.candidates.isNotEmpty ? m.candidates.first : null;
          return InkWell(
            onTap: () => context.push('/movements/$id'),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (!m.isUnmatched)
                        const Padding(
                          padding: EdgeInsets.only(right: 6),
                          child: Icon(Icons.check_circle, size: 18),
                        ),
                      Expanded(
                        child: Text(
                          '${vnd(m.amount)}${out ? ' ↗' : ''} · ${m.memo ?? m.counterparty ?? ''} · ${displayTime(m.occurredAt)}',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (!m.isUnmatched)
                    Wrap(
                      spacing: 6,
                      children: [
                        statusChip(context, m.status),
                        if (m.classificationType != null)
                          Chip(
                            label: Text(_classLabel(m.classificationType!)),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                      ],
                    )
                  else ...[
                    Text(
                      cand != null
                          ? 'Có thể là: ${cand.description} - ${vnd(cand.amount)}'
                          : 'Chưa rõ là khoản gì.',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (cand != null) ...[
                          FilledButton.icon(
                            onPressed: busy ? null : () => state._match(m),
                            icon: const Icon(Icons.link, size: 18),
                            label: const Text('Ghép'),
                          ),
                          const SizedBox(width: 8),
                        ],
                        FilledButton.tonalIcon(
                          onPressed: busy ? null : () => state._classify(m),
                          icon: const Icon(Icons.arrow_drop_down),
                          label: const Text('Phân loại'),
                        ),
                        if (busy) ...[
                          const SizedBox(width: 12),
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

String _classLabel(String t) => switch (t) {
  'DEPOSIT' => 'Đặt cọc',
  'OWNER_MONEY' => 'Tiền cá nhân',
  'OTHER' => 'Khác',
  _ => 'Không rõ',
};
