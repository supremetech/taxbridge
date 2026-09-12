# Ghép hoặc phân loại tiền vào

Một khoản tiền vào từ ảnh chuyển khoản được đối soát với các đơn bán đã xác nhận nhưng
chưa thu tiền; khi không có đơn phù hợp, chủ hộ phân loại nó là đặt cọc, tiền chủ góp, khác
hoặc không rõ. **Tiền vào ngân hàng tăng, doanh thu không đổi** — hero moment của TaxBridge
(UC4 + UC5 ở `CLAUDE.md` §9). Cách chấm candidate và tính dashboard: plan backend §6–7;
DTO và status code: `contract/`.

## Sub-features

- `money-candidates` `GET /api/money-movements/{id}` trả tối đa 3 candidate là event
  `SALE + CONFIRMED + UNPAID` của business, điểm giảm dần; `candidates: []` khi không có.
- `money-match` `match {eventId}`: movement → `MATCHED`, event → `paymentStatus=PAID`;
  `collected` tăng, `receivable` giảm.
- `money-classify` `classify {type}` với `DEPOSIT | OWNER_MONEY | OTHER | UNKNOWN`:
  movement → `CLASSIFIED`, `unmatchedMoneyCount` giảm 1.
- `money-hero-revenue` sau capture ảnh chuyển khoản `bankIn` tăng; sau classify
  `DEPOSIT` / `OWNER_MONEY` `dashboard.revenue` không đổi (và `daily_records.summary.revenue`
  nếu ngày đã đóng).

## How to get to it (user POV)

- Home → **Chụp chuyển khoản** → (Simulator: **Dùng file demo** → `transfer_match.jpg`) →
  **Gửi** → Movement Detail có khối **Có thể là thanh toán cho:** → chọn candidate →
  **Ghép với giao dịch** → về Home.
- Home → **Chụp chuyển khoản** → `transfer_deposit.jpg` → Movement Detail không có candidate
  → **Đặt cọc** → SnackBar "Đã ghi nhận đặt cọc. Doanh thu hôm nay không đổi." → về Home.
- Home → **Tiền vào** (badge = `unmatchedMoneyCount`) → chạm một thẻ → Movement Detail.
- Đóng ngày / Lịch sử ngày → warning `UNMATCHED_MONEY` → nút **Xử lý** → Movement Detail.

## Handles

| Màn hình | Loại | Nhãn |
|---|---|---|
| Home | nút | `Chụp chuyển khoản`, `Tiền vào` (kèm badge số) |
| Home | dòng / card | `Tiền vào ngân hàng`, `Thuế khoán ước tính`, `Doanh thu`, `Tiền đã thu`, `Còn phải thu` |
| Home | banner (tự ẩn 4 s) | `Tiền vào +380.000đ · Doanh thu không đổi ✓` |
| Capture (transfer) | nút | `Dùng file demo`, `Gửi` |
| Movement Detail | khối | `Bằng chứng` — thumbnail ảnh CK dưới hàng chip, chạm → dialog phóng to, nút `Đóng` |
| Movement Detail | khối | `Có thể là thanh toán cho:` (ẩn khi không có candidate) |
| Movement Detail | nút | `Ghép với giao dịch`, `Đặt cọc`, `Tiền cá nhân`, `Khác`, `Không rõ` |
| Movement Detail | SnackBar | `Đã ghi nhận đặt cọc. Doanh thu hôm nay không đổi.` |
| Movement Detail / list | chip nguồn | `💬 Zalo` · `🎤 Voice` · `📷 Ảnh` (ẩn khi TEXT từ app) |
| Close day / Record detail | nút | `Xử lý` (trên mỗi warning) |

## Driving it with curl

Preconditions:

- Chạy từ thư mục `taxbridge-prompt/`. `B=http://localhost:8787` (hoặc ngrok / Functions);
  `curl $B/api/health` → `{"ok": true}`. `T` = token từ `POST $B/api/login` với account demo;
  `H="X-Session-Token: $T"`; `J='Content-Type: application/json'`;
  `D=$(TZ=Asia/Ho_Chi_Minh date +%F)`.
- Business có đúng một event `SALE` `CONFIRMED` `UNPAID` 450000, `counterparty` "chị Lan",
  `occurredAt` hôm nay (chạy xong kịch bản capture-confirm-sale là có). Gọi `eventId` là `EV`.
- Chưa có movement: `curl -s $B/api/money-movements -H "$H"` → `[]`. Mốc dashboard
  `curl -s "$B/api/dashboard?date=$D" -H "$H"`: `revenue: 450000, collected: 0,
  receivable: 450000, bankIn: 0, unmatchedMoneyCount: 0`.
- Hai ảnh demo `demo-assets/transfer_match.jpg` (450.000đ, `LAN 3HOP`, `NGUYEN THI LAN`) và
  `demo-assets/transfer_deposit.jpg` (380.000đ, `COC MINH`) — tạo tối 11/09, checklist §3.

- **Tạo khoản tiền qua capture.**
  `curl -s $B/api/captures -H "$H" -F type=IMAGE_TRANSFER -F file=@demo-assets/transfer_match.jpg`
  → HTTP `200`, `status: "DONE"`, `resultType: "MONEY_MOVEMENT"`, `resultId` (gọi là `M1`).
- **Xem candidate.** `curl -s $B/api/money-movements/$M1 -H "$H"` → `status: "UNMATCHED"`,
  `amount: 450000`, `candidates` có đúng một phần tử `eventId == EV`, `score >= 0.9`;
  `evidenceUrl` là URL Storage (không `null` trên prod): `curl -sI "$evidenceUrl"` → `200`, `image/jpeg`.
  Dashboard: `bankIn: 450000`, `unmatchedMoneyCount: 1`, `revenue` không đổi.
- **Ghép với event.**
  `curl -s $B/api/money-movements/$M1/match -H "$H" -H "$J" -d "{\"eventId\":\"$EV\"}"`
  → `200`, `status: "MATCHED"`, `matchedEventId == EV`, `candidates: []`.
  `curl -s $B/api/events/$EV -H "$H"` → `paymentStatus: "PAID"`. Dashboard:
  `collected: 450000`, `receivable: 0`, `unmatchedMoneyCount: 0`.
- **Tạo khoản tiền không khớp.**
  `curl -s $B/api/captures -H "$H" -F type=IMAGE_TRANSFER -F file=@demo-assets/transfer_deposit.jpg`
  → `resultId` (gọi là `M2`); `curl -s $B/api/money-movements/$M2 -H "$H"` →
  `amount: 380000`, `candidates: []`. Dashboard: `bankIn: 830000`, `unmatchedMoneyCount: 1`,
  `revenue: 450000` **không đổi**.
- **Phân loại đặt cọc — hero.** Đọc dashboard, classify, đọc lại.
  `curl -s "$B/api/dashboard?date=$D" -H "$H"` (lưu lại);
  `curl -s $B/api/money-movements/$M2/classify -H "$H" -H "$J" -d '{"type":"DEPOSIT"}'`
  → `200`, `status: "CLASSIFIED"`, `classificationType: "DEPOSIT"`;
  `curl -s "$B/api/dashboard?date=$D" -H "$H"` → `revenue`, `collected`, `receivable`,
  `bankIn` **giống hệt** lần đọc trước; chỉ `unmatchedMoneyCount` giảm `1` → `0`.
- **Sai trạng thái bị chặn.** Gọi lại `match` trên `M1` hoặc `classify` trên `M2` →
  `409 {"code": "INVALID_STATE"}`.
- **Bằng chứng.** `curl -s $B/api/money-movements -H "$H"` lưu thành JSON: `M1` `MATCHED` +
  `matchedEventId`, `M2` `CLASSIFIED` + `DEPOSIT`. Kèm hai output dashboard trước / sau classify.
- **Đối chiếu trên app (tuỳ chọn).** Trên Simulator mở Home rồi `inspect`: dòng
  `Tiền vào ngân hàng` = `830.000đ`, card `Doanh thu` = `450.000đ`, dòng `Thuế khoán ước tính`
  = `6.750đ` (không đổi so với trước classify), banner `Tiền vào +380.000đ · Doanh thu không
  đổi ✓` hiện ngay khi về Home, nút `Tiền vào` không còn badge. Mở `M2` từ danh sách Tiền vào:
  khối `Bằng chứng` dưới hàng chip là thumbnail ảnh 380k, chạm → phóng to.
