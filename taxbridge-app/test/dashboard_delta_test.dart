import 'package:flutter_test/flutter_test.dart';
import 'package:taxbridge_app/core/format.dart';
import 'package:taxbridge_app/features/home/home_screen.dart';
import 'package:taxbridge_app/models/dashboard.dart';

Dashboard _d({
  int revenue = 0,
  int expense = 0,
  int collected = 0,
  int receivable = 0,
  int bankIn = 0,
  int draftCount = 0,
  int unmatched = 0,
}) => Dashboard(
  date: '2026-09-12',
  revenue: revenue,
  expense: expense,
  collected: collected,
  receivable: receivable,
  bankIn: bankIn,
  draftCount: draftCount,
  unmatchedMoneyCount: unmatched,
);

void main() {
  test('vnd / estTax', () {
    expect(vnd(4820000), '4.820.000đ');
    expect(vnd(0), '0đ');
    expect(vndDelta(-450000), '−450.000đ');
    expect(estTax(450000), 6750);
    expect(estTax(4820000), 72300);
  });

  test('confirm SALE → Doanh thu + Còn phải thu', () {
    final prev = _d(draftCount: 1);
    final next = _d(revenue: 450000, receivable: 450000);
    expect(
      dashboardDelta(prev, next),
      'Doanh thu +450.000đ · Còn phải thu +450.000đ',
    );
  });

  test('hero: classify DEPOSIT → Tiền vào + Doanh thu không đổi', () {
    final prev = _d(revenue: 450000, receivable: 450000, bankIn: 0);
    final next = _d(revenue: 450000, receivable: 450000, bankIn: 380000);
    expect(
      dashboardDelta(prev, next),
      'Tiền vào +380.000đ · Doanh thu không đổi ✓',
    );
  });

  test('classify khi bankIn đã cập nhật trước đó → chỉ dòng không đổi', () {
    final prev = _d(revenue: 450000, bankIn: 380000, unmatched: 1);
    final next = _d(revenue: 450000, bankIn: 380000, unmatched: 0);
    expect(dashboardDelta(prev, next), 'Doanh thu không đổi ✓');
  });

  test('không đổi → null', () {
    final d = _d(revenue: 1);
    expect(dashboardDelta(d, d), isNull);
  });
}
