import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets.dart';
import '../../models/daily_record.dart';

/// Một dòng warning; nút **Xử lý** đưa tới Event / Movement Detail.
class WarningTile extends StatelessWidget {
  const WarningTile(this.w, {super.key});
  final DailyWarning w;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(
          w.isOpen ? Icons.warning_amber_rounded : Icons.check_circle_outline,
          color: w.isOpen
              ? Theme.of(context).colorScheme.tertiary
              : Theme.of(context).colorScheme.primary,
        ),
        title: Text(w.message),
        subtitle: Row(children: [statusChip(context, w.status)]),
        trailing: w.isOpen
            ? FilledButton.tonal(
                onPressed: () => context.push(w.route),
                child: const Text('Xử lý'),
              )
            : null,
        onTap: () => context.push(w.route),
      ),
    );
  }
}
