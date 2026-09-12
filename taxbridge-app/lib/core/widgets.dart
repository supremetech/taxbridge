import 'package:flutter/material.dart';

import 'api_client.dart';
import 'format.dart';

/// Chip nguồn: ZALO → 💬 Zalo; AUDIO → 🎤 Voice; IMAGE_* → 📷 Ảnh; TEXT từ app → null.
Widget? sourceChip(String source, String captureType) {
  final String? label;
  if (source == 'ZALO') {
    label = '💬 Zalo';
  } else if (captureType == 'AUDIO') {
    label = '🎤 Voice';
  } else if (captureType.startsWith('IMAGE')) {
    label = '📷 Ảnh';
  } else {
    label = null;
  }
  if (label == null) return null;
  return Chip(
    label: Text(label),
    visualDensity: VisualDensity.compact,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );
}

Color statusColor(BuildContext context, String status) {
  final cs = Theme.of(context).colorScheme;
  return switch (status) {
    'DRAFT' || 'UNMATCHED' || 'OPEN' => cs.tertiaryContainer,
    'CONFIRMED' ||
    'MATCHED' ||
    'CLASSIFIED' ||
    'RESOLVED' => cs.primaryContainer,
    'REJECTED' => cs.errorContainer,
    _ => cs.surfaceContainerHighest,
  };
}

Widget statusChip(BuildContext context, String status) => Chip(
  label: Text(status),
  backgroundColor: statusColor(context, status),
  visualDensity: VisualDensity.compact,
  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
);

/// 4 số summary + dòng Thuế khoán ước tính (Close day + Record detail + Báo cáo).
/// [bankIn] có → thêm dòng 🏦 Tiền vào ngân hàng (Báo cáo).
class SummaryGrid extends StatelessWidget {
  const SummaryGrid({
    super.key,
    required this.revenue,
    required this.collected,
    required this.receivable,
    required this.expense,
    this.bankIn,
  });

  final int revenue;
  final int collected;
  final int receivable;
  final int expense;
  final int? bankIn;

  @override
  Widget build(BuildContext context) {
    Widget cell(String label, int v) => Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 4),
              Text(
                vnd(v),
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
    return Column(
      children: [
        Row(
          children: [
            cell('Doanh thu', revenue),
            cell('Tiền đã thu', collected),
          ],
        ),
        Row(
          children: [
            cell('Còn phải thu', receivable),
            cell('Chi phí', expense),
          ],
        ),
        if (bankIn != null)
          ListTile(
            leading: const Text('🏦', style: TextStyle(fontSize: 20)),
            title: const Text('Tiền vào ngân hàng'),
            trailing: Text(
              vnd(bankIn!),
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
        ListTile(
          dense: true,
          leading: const Icon(Icons.receipt_long_outlined),
          title: const Text('Thuế khoán ước tính (1,5% DT)'),
          trailing: Text(
            vnd(estTax(revenue)),
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
      ],
    );
  }
}

/// SnackBar chung; riêng cho vài mã lỗi theo plan §8.
void showError(BuildContext context, Object e, {String? fallback}) {
  var msg = fallback ?? 'Có lỗi xảy ra. Vui lòng thử lại.';
  if (e is ApiException) {
    if (e.code == 'USERNAME_TAKEN') msg = 'Username đã tồn tại';
    if (e.code == 'INVALID_STATE') msg = 'Trạng thái không hợp lệ. Đã làm mới.';
  }
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

void showInfo(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

/// Overlay chờ dùng chung khi gọi mutation.
class BusyOverlay extends StatelessWidget {
  const BusyOverlay({
    super.key,
    required this.busy,
    required this.child,
    this.text,
  });
  final bool busy;
  final Widget child;
  final String? text;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      child,
      if (busy)
        Positioned.fill(
          child: ColoredBox(
            color: Colors.black38,
            child: Center(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      if (text != null) ...[
                        const SizedBox(height: 12),
                        Text(text!),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

/// Trạng thái lỗi của FutureProvider với nút thử lại.
class ErrorRetry extends StatelessWidget {
  const ErrorRetry({super.key, required this.onRetry, this.message});
  final VoidCallback onRetry;
  final String? message;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(message ?? 'Có lỗi xảy ra. Vui lòng thử lại.'),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: onRetry, child: const Text('Thử lại')),
      ],
    ),
  );
}

/// Thẻ trong list Events / Movements: tiêu đề + dòng phụ + hàng chip (không overflow như ListTile.trailing).
class ListCard extends StatelessWidget {
  const ListCard({
    super.key,
    required this.title,
    required this.lines,
    required this.chips,
    required this.onTap,
    this.leading,
  });

  final String title;
  final List<String> lines;
  final List<Widget> chips;
  final VoidCallback onTap;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 12)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    for (final l in lines.where((l) => l.isNotEmpty))
                      Text(l, style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [for (final c in chips) c],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
