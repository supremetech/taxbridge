# Tồn đọng: giao dịch chưa xử lý ở các ngày trước và tin nhắn Zalo cũ

Nháp chưa xác nhận / tiền vào chưa phân loại của những ngày trước không còn "rơi" khỏi Home:
Home cảnh báo và màn **Tồn đọng** gom theo ngày. Người dùng liên kết Zalo muộn thì tin nhắn đã
gửi trước đó được xử lý lại thành nháp (Phase 2 ③). DTO: `pending.json`, `replay_result.json`;
backend: plan BE §14; app: plan FE §12.

## Sub-features

- `pending-counts` `dashboard.pastDraftCount` / `pastUnmatchedCount` = DRAFT / UNMATCHED có ngày < `date`.
- `pending-list` `GET /api/pending` mọi ngày, cũ nhất trước, `byDate`.
- `pending-home` Home card cảnh báo + badge nút **Tồn đọng** (ẩn khi 0).
- `pending-resolve` xử lý từ Tồn đọng → detail v1 → về Home ngày bản ghi; tồn đọng giảm.
- `zalo-replay` `POST /api/zalo-users/{zaloId}/replay` sau register → nháp `source: ZALO` từ message cũ.

## How to get to it (user POV)

- Home (hôm nay) → card `⚠ Còn 1 giao dịch · 1 khoản tiền chưa xử lý từ các ngày trước` → Tồn đọng →
  chạm nháp 180k ngày 11/09 → **Xác nhận** → Home 11/09.
- Home → **Tồn đọng** (badge).
- Đăng ký → chọn Zalo account → **Đăng ký** → SnackBar `Đã xử lý 2 tin nhắn Zalo cũ` → Home badge Giao dịch +2.

## Handles

| Màn hình | Loại | Nhãn |
|---|---|---|
| Home | nút | `Tồn đọng` (kèm badge) |
| Home | card | `⚠ Còn n giao dịch · m khoản tiền chưa xử lý từ các ngày trước` |
| Tồn đọng | header | `11/09/2026 · 1 nháp · 1 tiền vào` |
| Tồn đọng | empty | `Không còn giao dịch tồn đọng` |
| Register | SnackBar | `Đã xử lý n tin nhắn Zalo cũ` |

## Driving it with curl

Preconditions: như `doc-date-home.md`; có ≥ 1 DRAFT và ≥ 1 UNMATCHED ngày `$D0` (chạy
`receipt.jpg` không confirm + `transfer_deposit.jpg` không classify); hôm nay `$D > $D0`.

- **Đếm tồn đọng.** `curl -s "$B/api/dashboard?date=$D" -H "$H"` → `pastDraftCount ≥ 1`,
  `pastUnmatchedCount ≥ 1`; `curl -s "$B/api/dashboard?date=$D0" -H "$H"` → cả hai `0` (không có ngày trước đó).
- **Danh sách.** `curl -s $B/api/pending -H "$H"` → `draftEvents[0].occurredAt` ≤ phần tử sau (tăng dần);
  `unmatchedMovements[].candidates` có key; `byDate` có dòng `$D0` với `draftCount`, `unmatchedCount`.
- **Xử lý → giảm.** Confirm draft đó → `pending` `draftEvents` −1, `dashboard?date=$D` `pastDraftCount` −1.
- **Replay Zalo.** Gửi `webhook_text.json` + `webhook_image.json` với `zaloId` **chưa link** (UC8) →
  register account mới với `zaloId` → `curl -s -X POST $B/api/zalo-users/$ZALO_ID/replay -H "$H2"`
  → `{replayed: 2, done: ≥1, failed: ≤1, skipped: 0}` (ảnh Zalo thật có thể hết hạn → failed);
  `curl -s "$B/api/events?status=DRAFT" -H "$H2"` có draft `source: ZALO`. Gọi lại → `replayed: 0`.
  `zaloId` không thuộc account → `404`.
- **Đối chiếu trên app.** Simulator Home hôm nay: `inspect` card `⚠ Còn …`, nút `Tồn đọng` có badge;
  vào Tồn đọng: header `11/09/2026 · …`; xử lý xong 2 bản ghi → quay lại thấy `Không còn giao dịch tồn đọng`.
