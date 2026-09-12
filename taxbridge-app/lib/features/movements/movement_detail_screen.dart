import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/evidence_block.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/widgets.dart';
import '../../models/money_movement.dart';

class MovementDetailScreen extends ConsumerStatefulWidget {
  const MovementDetailScreen({super.key, required this.id});
  final String id;

  @override
  ConsumerState<MovementDetailScreen> createState() =>
      _MovementDetailScreenState();
}

class _MovementDetailScreenState extends ConsumerState<MovementDetailScreen> {
  String? _selected; // candidate eventId
  bool _busy = false;

  Future<void> _run(
    Future<MoneyMovement> Function() fn, {
    String? successMsg,
  }) async {
    setState(() => _busy = true);
    try {
      await fn();
      invalidateAll(ref);
      if (!mounted) return;
      if (successMsg != null) showInfo(context, successMsg);
      context.go(
        '/home',
      ); // về Home để thấy số đổi ngay (pop sẽ về màn Capture)
    } catch (e) {
      if (!mounted) return;
      showError(context, e);
      ref.invalidate(movementProvider(widget.id));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _match() {
    final ev = _selected;
    if (ev == null) return;
    _run(() => ref.read(apiProvider).matchMovement(widget.id, ev));
  }

  void _classify(String type) => _run(
    () => ref.read(apiProvider).classifyMovement(widget.id, type),
    successMsg: type == 'DEPOSIT'
        ? 'Đã ghi nhận đặt cọc. Doanh thu hôm nay không đổi.'
        : null,
  );

  @override
  Widget build(BuildContext context) {
    final mv = ref.watch(movementProvider(widget.id));
    return Scaffold(
      appBar: AppBar(title: const Text('Khoản tiền vào')),
      body: BusyOverlay(
        busy: _busy,
        child: mv.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorRetry(
            onRetry: () => ref.invalidate(movementProvider(widget.id)),
          ),
          data: (m) => _body(context, m),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, MoneyMovement m) {
    final theme = Theme.of(context);
    final chip = sourceChip(m.source, m.captureType);
    _selected ??= m.candidates.isNotEmpty ? m.candidates.first.eventId : null;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          vnd(m.amount),
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          [m.counterparty, m.memo].whereType<String>().join(' · '),
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            statusChip(context, m.status),
            if (m.classificationType != null)
              Chip(label: Text(m.classificationType!)),
            if (m.matchedEventId != null)
              ActionChip(
                label: Text('Đơn ${m.matchedEventId}'),
                onPressed: () => context.push('/events/${m.matchedEventId}'),
              ),
            ?chip,
          ],
        ),
        const SizedBox(height: 12),
        EvidenceBlock(
          captureType: m.captureType,
          evidenceText: m.evidenceText,
          evidenceUrl: m.evidenceUrl,
        ),
        const SizedBox(height: 16),
        if (m.isUnmatched) ...[
          if (m.candidates.isNotEmpty) ...[
            Text(
              'Có thể là thanh toán cho:',
              style: theme.textTheme.titleMedium,
            ),
            RadioGroup<String>(
              groupValue: _selected,
              onChanged: (v) => setState(() => _selected = v),
              child: Column(
                children: [
                  for (final c in m.candidates)
                    RadioListTile<String>(
                      value: c.eventId,
                      title: Text('${c.description} - ${vnd(c.amount)}'),
                      subtitle: Text('Độ khớp ${(c.score * 100).round()}%'),
                    ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: _selected == null || _busy ? null : _match,
              icon: const Icon(Icons.link),
              label: const Text('Ghép với giao dịch'),
            ),
            const Divider(height: 32),
            Text('Hoặc phân loại:', style: theme.textTheme.titleMedium),
          ] else ...[
            Text(
              '${vnd(m.amount)} từ ${m.counterparty ?? 'người gửi'} chưa rõ là khoản gì.',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text('Khoản này là gì?', style: theme.textTheme.bodyLarge),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonal(
                onPressed: _busy ? null : () => _classify('DEPOSIT'),
                child: const Text('Đặt cọc'),
              ),
              FilledButton.tonal(
                onPressed: _busy ? null : () => _classify('OWNER_MONEY'),
                child: const Text('Tiền cá nhân'),
              ),
              FilledButton.tonal(
                onPressed: _busy ? null : () => _classify('OTHER'),
                child: const Text('Khác'),
              ),
              FilledButton.tonal(
                onPressed: _busy ? null : () => _classify('UNKNOWN'),
                child: const Text('Không rõ'),
              ),
            ],
          ),
        ] else
          Text(
            m.status == 'MATCHED'
                ? 'Khoản tiền đã được ghép với giao dịch.'
                : 'Khoản tiền đã được phân loại.',
            style: theme.textTheme.bodyMedium,
          ),
      ],
    );
  }
}
