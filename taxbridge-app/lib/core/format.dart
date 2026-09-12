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

String displayTime(DateTime? d) =>
    d == null ? '' : DateFormat('dd/MM HH:mm').format(d.toLocal());

/// Thuế khoán ước tính hộ bán lẻ: GTGT 1% + TNCN 0,5% (PoC bỏ qua ngưỡng miễn thuế).
int estTax(int revenue) => (revenue * 0.015).round();
