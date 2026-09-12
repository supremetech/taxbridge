import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/evidence_block.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/widgets.dart';
import '../../models/business_event.dart';

const _types = ['SALE', 'PURCHASE', 'DEPOSIT', 'OWNER_MONEY', 'UNKNOWN'];
const _methods = ['CASH', 'BANK', 'UNKNOWN'];
const _payStatuses = ['UNPAID', 'PAID', 'UNKNOWN'];

class EventDetailScreen extends ConsumerWidget {
  const EventDetailScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ev = ref.watch(eventProvider(id));
    return Scaffold(
      appBar: AppBar(title: const Text('Chi tiết giao dịch')),
      body: ev.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            ErrorRetry(onRetry: () => ref.invalidate(eventProvider(id))),
        data: (e) => _EventForm(key: ValueKey(e.eventId + e.status), event: e),
      ),
    );
  }
}

class _EventForm extends ConsumerStatefulWidget {
  const _EventForm({super.key, required this.event});
  final BusinessEvent event;

  @override
  ConsumerState<_EventForm> createState() => _EventFormState();
}

class _EventFormState extends ConsumerState<_EventForm> {
  late String _type = _pick(widget.event.type, _types);
  late String _method = _pick(widget.event.paymentMethod, _methods);
  late String _payStatus = _pick(widget.event.paymentStatus, _payStatuses);
  late final _amount = TextEditingController(
    text: widget.event.amount.toString(),
  );
  late final _desc = TextEditingController(
    text: widget.event.description ?? '',
  );
  late final _party = TextEditingController(
    text: widget.event.counterparty ?? '',
  );
  late DateTime? _occurredAt = widget.event.occurredAt?.toLocal();
  bool _busy = false;

  BusinessEvent get e => widget.event;
  bool get editable => e.isDraft;

  static String _pick(String? v, List<String> options) =>
      options.contains(v) ? v! : options.last;

  @override
  void dispose() {
    _amount.dispose();
    _desc.dispose();
    _party.dispose();
    super.dispose();
  }

  /// Chỉ các field khác bản gốc (PUT partial).
  Map<String, dynamic> _patch() {
    final p = <String, dynamic>{};
    if (_type != e.type) p['type'] = _type;
    final amt = int.tryParse(_amount.text.replaceAll(RegExp(r'[^0-9]'), ''));
    if (amt != null && amt != e.amount) p['amount'] = amt;
    final desc = _desc.text.trim();
    final party = _party.text.trim();
    if (desc != (e.description ?? '')) p['description'] = desc;
    if (party != (e.counterparty ?? '')) p['counterparty'] = party;
    if (_method != e.paymentMethod) p['paymentMethod'] = _method;
    if (_payStatus != e.paymentStatus) p['paymentStatus'] = _payStatus;
    final at = _occurredAt;
    if (at != null && e.occurredAt != null && at != e.occurredAt!.toLocal()) {
      p['occurredAt'] = _iso7(at);
    }
    return p;
  }

  /// ISO-8601 với offset máy (VN = +07:00), không dùng `Z`.
  static String _iso7(DateTime d) {
    final off = d.timeZoneOffset;
    final sign = off.isNegative ? '-' : '+';
    final hh = off.inHours.abs().toString().padLeft(2, '0');
    final mm = (off.inMinutes.abs() % 60).toString().padLeft(2, '0');
    final base = d.toIso8601String().split('.').first;
    return '$base$sign$hh:$mm';
  }

  /// Ô Ngày (Phase 2 ②): đổi ngày, giữ giờ cũ.
  Future<void> _pickDate() async {
    final cur = _occurredAt ?? DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: cur,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (d == null) return;
    setState(
      () => _occurredAt = DateTime(
        d.year,
        d.month,
        d.day,
        cur.hour,
        cur.minute,
        cur.second,
      ),
    );
  }

  Future<void> _confirm() async {
    setState(() => _busy = true);
    try {
      final api = ref.read(apiProvider);
      final patch = _patch();
      await prepareReturnToDate(
        ref,
        _occurredAt,
        drafts: 1,
      ); // Home về ngày bản ghi
      if (patch.isNotEmpty) await api.updateEvent(e.eventId, patch);
      await api.confirmEvent(e.eventId);
      invalidateAll(ref);
      if (mounted) context.go('/home');
    } catch (err) {
      if (!mounted) return;
      showError(context, err);
      ref.invalidate(eventProvider(e.eventId));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    setState(() => _busy = true);
    try {
      await prepareReturnToDate(ref, e.occurredAt, drafts: 1);
      await ref.read(apiProvider).rejectEvent(e.eventId);
      invalidateAll(ref);
      if (mounted) context.go('/home');
    } catch (err) {
      if (!mounted) return;
      showError(context, err);
      ref.invalidate(eventProvider(e.eventId));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chip = sourceChip(e.source, e.captureType);
    return BusyOverlay(
      busy: _busy,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('Trạng thái'),
              statusChip(context, e.status),
              if (e.confidence != null)
                Chip(
                  label: Text('AI ${(e.confidence! * 100).round()}%'),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ?chip,
            ],
          ),
          const SizedBox(height: 12),
          EvidenceBlock(
            captureType: e.captureType,
            evidenceText: e.evidenceText,
            evidenceUrl: e.evidenceUrl,
          ),
          const SizedBox(height: 16),
          _dropdown('Loại', _type, _types, (v) => setState(() => _type = v)),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            enabled: editable,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Số tiền',
              suffixText: 'đ',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _desc,
            enabled: editable,
            decoration: const InputDecoration(
              labelText: 'Nội dung',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _party,
            enabled: editable,
            decoration: const InputDecoration(
              labelText: 'Khách',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: editable ? _pickDate : null,
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Ngày',
                border: OutlineInputBorder(),
                suffixIcon: Icon(Icons.calendar_today_outlined),
              ),
              child: Text(
                _occurredAt == null ? '' : displayDate(dateKey(_occurredAt!)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _dropdown(
            'Thanh toán',
            _method,
            _methods,
            (v) => setState(() => _method = v),
          ),
          const SizedBox(height: 12),
          _dropdown(
            'Thu tiền',
            _payStatus,
            _payStatuses,
            (v) => setState(() => _payStatus = v),
          ),
          const SizedBox(height: 24),
          if (editable)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : _reject,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                    child: const Text('Từ chối'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _busy ? null : _confirm,
                    child: const Text('Xác nhận'),
                  ),
                ),
              ],
            )
          else
            Text(
              e.status == 'CONFIRMED'
                  ? 'Giao dịch đã được xác nhận.'
                  : 'Giao dịch đã bị từ chối.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
        ],
      ),
    );
  }

  Widget _dropdown(
    String label,
    String value,
    List<String> options,
    ValueChanged<String> onChanged,
  ) => DropdownButtonFormField<String>(
    initialValue: value,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
    items: [
      for (final o in options) DropdownMenuItem(value: o, child: Text(o)),
    ],
    onChanged: editable ? (v) => v == null ? null : onChanged(v) : null,
  );
}
