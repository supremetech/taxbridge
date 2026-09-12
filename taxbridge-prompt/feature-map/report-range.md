# Báo cáo doanh thu, giao dịch theo khoảng thời gian

Chủ hộ chọn `Hôm nay / 7 ngày / Tháng này / Tháng trước / Tùy chọn` và thấy tổng doanh thu, chi
phí, tiền đã thu, còn phải thu, tiền vào ngân hàng, thuế khoán ước tính của cả kỳ, bảng theo ngày
và theo loại (Phase 2 ④). DTO: `contract/fixtures/report.json`; backend: plan BE §13; app: plan FE §11.

## Sub-features

- `report-range` `GET /api/reports?from&to` tổng hợp CONFIRMED trong `[from, to]`; ≤ 92 ngày.
- `report-by-day` `byDay` chỉ ngày có dữ liệu, mới nhất trước; số ngày = `dashboard` ngày đó.
- `report-by-type` `byType` gộp CONFIRMED theo `BusinessEvent.type`.
- `report-presets` chip preset tính ở client; `Tùy chọn` mở date range picker.
- `report-drill` chạm dòng ngày → Home của ngày đó.

## How to get to it (user POV)

- Home → **Báo cáo** → chip **7 ngày** → xem số → chạm dòng `11/09/2026` → Home 11/09.
- Home → **Báo cáo** → **Tùy chọn** → chọn 01/09–12/09 → **Lưu**.

## Handles

| Màn hình | Loại | Nhãn |
|---|---|---|
| Home | nút | `Báo cáo` |
| Báo cáo | chip | `Hôm nay`, `7 ngày`, `Tháng này`, `Tháng trước`, `Tùy chọn` |
| Báo cáo | dòng | `06/09/2026 – 12/09/2026 · 7 ngày`, `Tiền vào ngân hàng`, `Thuế khoán ước tính` |
| Báo cáo | khối | `Theo ngày`, `Theo loại` |

## Driving it with curl

Preconditions: như `match-classify-money.md`; đã có dữ liệu ngày `$D0=2026-09-11` (3 ảnh demo) và
hôm nay `$D` (text/voice). `F=$(TZ=Asia/Ho_Chi_Minh date -v-6d +%F)` (macOS).

- **7 ngày.** `curl -s "$B/api/reports?from=$F&to=$D" -H "$H"` → `days: 7`; `summary.revenue` =
  Σ `byDay[].revenue`; `byDay[0].date == $D` (nếu hôm nay có dữ liệu), có dòng `$D0` với `revenue`
  = `curl -s "$B/api/dashboard?date=$D0" -H "$H" | jq .revenue`.
- **Theo loại.** `byType` có `SALE` (`count` = số SALE CONFIRMED), `PURCHASE`; không có type `count: 0`.
- **Validation.** Thiếu `to` → `400 VALIDATION_ERROR`; `from=2026-01-01&to=2026-09-12` (> 92 ngày) → `400`;
  `to < from` → `400`.
- **Sau confirm số đổi.** Confirm một nháp SALE hôm nay → gọi lại report → `summary.revenue` +amount,
  `byDay` dòng `$D` +amount.
- **Đối chiếu trên app.** Simulator: Home → `Báo cáo` → chip `7 ngày`; `inspect` `Doanh thu` = `summary.revenue`
  định dạng `vnd`; dòng `Thuế khoán ước tính` = `round(revenue × 0,015)`; chạm dòng `11/09/2026` → Home
  hiện `Thứ Sáu, 11/09/2026`.
