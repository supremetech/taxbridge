import 'package:intl/intl.dart';

final _vnd = NumberFormat('#,##0', 'vi_VN');

/// 4820000 → `4.820.000đ`
String vnd(int amount) => '${_vnd.format(amount)}đ';

/// Delta có dấu: `+450.000đ` / `−450.000đ`
String vndDelta(int delta) => delta >= 0 ? '+${vnd(delta)}' : '−${vnd(-delta)}';

/// Ngày nghiệp vụ `yyyy-MM-dd`
String dateKey(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
String todayKey() => dateKey(DateTime.now());

/// `2026-09-11` → `11/09/2026`
String displayDate(String key) {
  final d = DateTime.tryParse(key);
  return d == null ? key : DateFormat('dd/MM/yyyy').format(d);
}

const _weekdays = [
  'Thứ Hai',
  'Thứ Ba',
  'Thứ Tư',
  'Thứ Năm',
  'Thứ Sáu',
  'Thứ Bảy',
  'Chủ Nhật',
];

/// `2026-09-11` → `Thứ Sáu, 11/09/2026` (không cần initializeDateFormatting).
String displayDateLong(String key) {
  final d = DateTime.tryParse(key);
  if (d == null) return key;
  return '${_weekdays[d.weekday - 1]}, ${displayDate(key)}';
}

String displayTime(DateTime? d) =>
    d == null ? '' : DateFormat('dd/MM HH:mm').format(d.toLocal());

/// Thuế khoán ước tính hộ bán lẻ: GTGT 1% + TNCN 0,5% (PoC bỏ qua ngưỡng miễn thuế).
int estTax(int revenue) => (revenue * 0.015).round();

// ---- khoảng ngày cho Báo cáo (Phase 2 ④); `to` không vượt hôm nay ----

typedef DateRange = ({String from, String to});

DateRange rangeToday() => (from: todayKey(), to: todayKey());

DateRange rangeLast7() {
  final now = DateTime.now();
  return (
    from: dateKey(now.subtract(const Duration(days: 6))),
    to: dateKey(now),
  );
}

DateRange rangeThisMonth() {
  final now = DateTime.now();
  return (from: dateKey(DateTime(now.year, now.month, 1)), to: dateKey(now));
}

DateRange rangeLastMonth() {
  final now = DateTime.now();
  final first = DateTime(now.year, now.month - 1, 1);
  final last = DateTime(now.year, now.month, 0);
  return (from: dateKey(first), to: dateKey(last));
}

/// `06/09/2026 – 12/09/2026 · 7 ngày`
String displayRange(DateRange r, int days) =>
    '${displayDate(r.from)} – ${displayDate(r.to)} · $days ngày';
