import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/widgets.dart';
import '../../models/money_movement.dart';

class MovementListScreen extends StatelessWidget {
  const MovementListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Tiền vào'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Tất cả'),
              Tab(text: 'Chưa xử lý'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [_MovementList(null), _MovementList('UNMATCHED')],
        ),
      ),
    );
  }
}

class _MovementList extends ConsumerWidget {
  const _MovementList(this.status);
  final String? status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(moneyMovementsProvider(status));
    return RefreshIndicator(
      onRefresh: () => ref.refresh(moneyMovementsProvider(status).future),
      child: list.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorRetry(
          onRetry: () => ref.invalidate(moneyMovementsProvider(status)),
        ),
        data: (items) => items.isEmpty
            ? ListView(
                children: const [
                  SizedBox(height: 120),
                  Center(child: Text('Chưa có khoản tiền vào nào')),
                ],
              )
            : ListView.builder(
                itemCount: items.length,
                itemBuilder: (_, i) => _MovementCard(items[i]),
              ),
      ),
    );
  }
}

class _MovementCard extends StatelessWidget {
  const _MovementCard(this.m);
  final MoneyMovement m;

  @override
  Widget build(BuildContext context) {
    final chip = sourceChip(m.source, m.captureType);
    final status = m.classificationType != null
        ? '${m.status} · ${m.classificationType}'
        : m.status;
    return ListCard(
      onTap: () => context.push('/movements/${m.movementId}'),
      leading: Icon(
        m.direction == 'IN' ? Icons.south_west : Icons.north_east,
        color: Theme.of(context).colorScheme.primary,
      ),
      title: '${vnd(m.amount)} · ${m.counterparty ?? ''}',
      lines: [m.memo ?? '', displayTime(m.occurredAt)],
      chips: [statusChip(context, status), ?chip],
    );
  }
}
