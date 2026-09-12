import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/widgets.dart';
import '../../models/business_event.dart';

const _typeLabel = {
  'SALE': 'Bán hàng',
  'PURCHASE': 'Mua hàng',
  'DEPOSIT': 'Đặt cọc',
  'OWNER_MONEY': 'Tiền cá nhân',
  'UNKNOWN': 'Không rõ',
};

String eventTypeLabel(String t) => _typeLabel[t] ?? t;

class EventListScreen extends StatelessWidget {
  const EventListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Giao dịch'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Tất cả'),
              Tab(text: 'Nháp'),
              Tab(text: 'Đã xác nhận'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _EventList(null),
            _EventList('DRAFT'),
            _EventList('CONFIRMED'),
          ],
        ),
      ),
    );
  }
}

class _EventList extends ConsumerWidget {
  const _EventList(this.status);
  final String? status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(eventsProvider(status));
    return RefreshIndicator(
      onRefresh: () => ref.refresh(eventsProvider(status).future),
      child: list.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            ErrorRetry(onRetry: () => ref.invalidate(eventsProvider(status))),
        data: (events) => events.isEmpty
            ? ListView(
                children: const [
                  SizedBox(height: 120),
                  Center(child: Text('Chưa có giao dịch nào')),
                ],
              )
            : ListView.builder(
                itemCount: events.length,
                itemBuilder: (_, i) => EventCard(events[i]),
              ),
      ),
    );
  }
}

class EventCard extends StatelessWidget {
  const EventCard(this.e, {super.key});
  final BusinessEvent e;

  @override
  Widget build(BuildContext context) {
    final chip = sourceChip(e.source, e.captureType);
    final sub = [
      if (e.counterparty != null) e.counterparty!,
      if (e.paymentMethod != null) e.paymentMethod!,
      if (e.paymentStatus != null) e.paymentStatus!,
      displayTime(e.occurredAt),
    ].where((s) => s.isNotEmpty).join(' · ');
    return ListCard(
      onTap: () => context.push('/events/${e.eventId}'),
      title: '${eventTypeLabel(e.type)} · ${vnd(e.amount)}',
      lines: [e.description ?? '', sub],
      chips: [statusChip(context, e.status), ?chip],
    );
  }
}
