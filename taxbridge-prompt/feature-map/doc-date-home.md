# Ghi nhận theo ngày trên chứng từ và Home theo ngày

Chứng từ chụp hôm nay nhưng in ngày hôm qua thì vào sổ ngày hôm qua; Home lật được từng
ngày, và sau khi xử lý một bản ghi app đưa người dùng về Home **của ngày bản ghi đó**, nên
hero `Tiền vào +380.000đ · Doanh thu không đổi ✓` vẫn hiện dù ảnh demo in `11/09/2026`
(Phase 2 ②, `requirements-phase2.md`). Rule fallback ngày: `contract/README.md` §5.2; backend:
plan BE §12; app: plan FE §10.

## Sub-features

- `date-from-image` capture ảnh → `occurredAt` = ngày (+ giờ) in trên ảnh; `CaptureResult.occurredAt`.
- `date-fallback-now` text/voice không nêu ngày, hoặc ngày không hợp lệ → `now()`.
- `date-sync-record` bản ghi mới rơi vào ngày đã đóng → `daily_records/{date}` có warning mới, `summary` mới.
- `home-by-date` Home có ‹ › + **Hôm nay**; `dashboard?date=` theo ngày đang xem.
- `home-return-date` sau confirm / match / classify → Home của ngày bản ghi, banner delta đúng.
- `event-edit-date` Event Detail sửa **Ngày** khi DRAFT → PUT `occurredAt`.

## How to get to it (user POV)

- Home → **Chụp chuyển khoản** → **Dùng file demo** → `transfer_deposit.jpg` → **Gửi** → Movement
  Detail (dòng ngày `11/09 11:02`) → **Đặt cọc** → Home tự lật về `11/09/2026`, banner hero.
- Home → **‹** / **›** / **Hôm nay** để lật ngày.
- Home → **Giao dịch** → một nháp → ô **Ngày** → chọn ngày khác → **Xác nhận** → Home ngày mới.

## Handles

| Màn hình | Loại | Nhãn |
|---|---|---|
| Home | nút | `‹`, `›` (IconButton, tooltip `Ngày trước` / `Ngày sau`), `Hôm nay` |
| Home | dòng | `Thứ Sáu, 11/09/2026` (ngày đang xem, `EEEE, dd/MM/yyyy` vi) |
| Capture | SnackBar | `Ghi vào ngày 11/09/2026` (chỉ khi khác hôm nay) |
| Event Detail | ô nhập | `Ngày` |
| Movement Detail | dòng | `11/09 11:02` dưới số tiền |

## Driving it with curl

Preconditions: như `match-classify-money.md`; thêm `D0=2026-09-11` (ngày in trên 3 ảnh demo) và
`daily_records/$D0` **đã tồn tại** (seed prod hoặc `POST /api/close-day {"date":"2026-09-11"}`).

- **Ảnh in ngày cũ.** `curl -s $B/api/captures -H "$H" -F type=IMAGE_TRANSFER -F file=@demo-assets/transfer_deposit.jpg`
  → `status: DONE`, `occurredAt` bắt đầu `2026-09-11T11:02` (gọi `M2`).
  `curl -s "$B/api/dashboard?date=$D0" -H "$H"` → `bankIn` +380000, `unmatchedMoneyCount` +1;
  `curl -s "$B/api/dashboard?date=$D" -H "$H"` (hôm nay) → **không đổi**.
- **Sổ ngày đã đóng tự cập nhật.** `curl -s $B/api/daily-records/$D0 -H "$H"` → `warnings` có
  `UNMATCHED_MONEY:$M2` `OPEN`, `warningCount` +1 (không cần gọi close-day).
- **Text không nêu ngày → hôm nay.** `curl -s $B/api/captures -H "$H" -H "$J" -d '{"type":"TEXT","text":"bán 1 hộp collagen 150k tiền mặt"}'`
  → `occurredAt` bắt đầu `$D`. Text nêu ngày: `"hôm qua bán 1 hộp collagen 150k tiền mặt"` →
  `occurredAt` bắt đầu `$D − 1`.
- **Classify → warning đóng.** `curl -s $B/api/money-movements/$M2/classify -H "$H" -H "$J" -d '{"type":"DEPOSIT"}'`
  → `curl -s $B/api/daily-records/$D0 -H "$H"` → warning đó `RESOLVED`, `summary.revenue` không đổi.
- **Sửa ngày nháp.** `curl -s -X PUT $B/api/events/$EV_DRAFT -H "$H" -H "$J" -d '{"occurredAt":"2026-09-10T12:00:00+07:00"}'`
  → `200`; `dashboard?date=2026-09-10` `draftCount` +1, ngày cũ −1; `occurredAt` sai format → `400`.
- **Đối chiếu trên app.** Simulator: sau **Đặt cọc**, `inspect` Home: dòng ngày = `Thứ Sáu, 11/09/2026`,
  banner `Tiền vào +380.000đ · Doanh thu không đổi ✓`, nút `Hôm nay` hiện; chạm `Hôm nay` → số về hôm nay.
