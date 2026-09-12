# Ghi nhận bán hàng bằng văn bản và xác nhận bản nháp

Chủ hộ gõ một câu bán hàng tự do từ Home, xem và sửa bản nháp AI trích xuất, rồi xác nhận
hoặc từ chối; về Home thấy Doanh thu trong ngày được làm mới. Đây là UC2 ở `CLAUDE.md` §9;
UC3 (voice) và UC6 (ảnh phiếu) đi cùng đường từ Event Detail trở đi.

## Sub-features

- `capture-open` mở màn nhập giao dịch bằng văn bản từ Home.
- `capture-submit` gửi văn bản; `POST /api/captures` (TEXT) trả `CaptureResult`, app mở
  Event Detail của `resultId`.
- `event-edit` sửa một trường trên bản nháp; chỉ gửi `PUT` lúc bấm Xác nhận.
- `event-confirm` xác nhận bản nháp, về Home; Doanh thu và Còn phải thu tăng.
- `event-reject` từ chối bản nháp; tab Nháp trên màn Giao dịch không còn thẻ đó.

## How to get to it (user POV)

- Home → nút **Nhập giao dịch** → ô **Nội dung** → nút **Gửi** → Event Detail.
- Home → nút **Giao dịch** → tab **Nháp** → chạm một thẻ → Event Detail.
- Event Detail → **Xác nhận** hoặc **Từ chối** → về Home.

## Handles

| Màn hình | Loại | Nhãn |
|---|---|---|
| Home | nút | `Nhập giao dịch`, `Nói giao dịch`, `Chụp chứng từ`, `Chụp chuyển khoản`, `Giao dịch`, `Tiền vào`, `Đóng ngày`, `Lịch sử ngày` |
| Home | card / dòng | `Doanh thu`, `Tiền đã thu`, `Còn phải thu`, `Chi phí`; dòng `Tiền vào ngân hàng`, `Thuế khoán ước tính` |
| Home | banner (tự ẩn 4 s) | `Doanh thu +450.000đ · Còn phải thu +450.000đ` |
| Capture (text) | ô nhập / nút | `Nội dung` / `Gửi` |
| Event Detail | chip | `Trạng thái` — giá trị `DRAFT` · `CONFIRMED` · `REJECTED`; chip nguồn `💬 Zalo` · `🎤 Voice` · `📷 Ảnh` |
| Event Detail | khối | `Bằng chứng` — text in nghiêng; voice: transcript + nút `Nghe lại`; ảnh: thumbnail, chạm → dialog phóng to, nút `Đóng` |
| Event Detail | ô nhập | `Loại`, `Số tiền`, `Nội dung`, `Khách`, `Thanh toán`, `Thu tiền` |
| Event Detail | nút | `Xác nhận`, `Từ chối` |
| Events | tab | `Tất cả`, `Nháp`, `Đã xác nhận` |

## Driving it with iOS Simulator + curl

Preconditions:

- Backend chạy `flask --app app.flask_app:create_app run --port 8787` với Firestore thật
  (`GCLOUD_PROJECT=hackathon-42790`). `B=http://localhost:8787`; `curl $B/api/health` →
  `{"ok": true}`.
- App chạy trên iOS Simulator:
  `flutter run --dart-define=API_BASE_URL=$B --dart-define=DEMO=true`. Đã đăng nhập account
  demo (`tuan` / `123456`); `T` = token của account đó từ `POST $B/api/login`;
  `H="X-Session-Token: $T"`; `D=$(TZ=Asia/Ho_Chi_Minh date +%F)`.
- Business chưa có event `DRAFT`; `curl -s "$B/api/dashboard?date=$D" -H "$H"` có `revenue: 0`.

- **Mở màn nhập.** Bấm **Nhập giao dịch** trên Home. `inspect marker="Nhập giao dịch"` →
  `tap` tâm `frame`. Cây accessibility có ô `Nội dung` và nút `Gửi`.
- **Nhập và gửi.** Gõ câu bán hàng rồi gửi. `tap` ô `Nội dung`,
  `text "Bán 3 hộp collagen 450 nghìn chuyển khoản"`, `tap` nút `Gửi`. Overlay "Đang đọc…"
  rồi Event Detail: chip `Trạng thái` = `DRAFT`, `Loại` = `SALE`, `Số tiền` = `450000`,
  `Thanh toán` = `BANK`, `Thu tiền` = `UNPAID`; khối `Bằng chứng` hiện nguyên câu vừa gõ. Đối chiếu:
  `curl -s "$B/api/events?status=DRAFT" -H "$H"` có đúng một event với `evidenceText` = câu vừa gõ, `evidenceUrl: null`; gọi `eventId` là `EV`.
- **Sửa trước khi xác nhận.** Đổi tên khách. `tap` ô `Khách`, xóa, `text "chị Lan"`. Chưa có
  request nào: `curl -s $B/api/events/$EV -H "$H"` vẫn trả `counterparty` cũ.
- **Xác nhận.** `tap` nút `Xác nhận`. App về Home: banner `Doanh thu +450.000đ · Còn phải thu
  +450.000đ`; card `Doanh thu` = `450.000đ`, `Còn phải thu` = `450.000đ`, `Tiền đã thu` = `0đ`,
  dòng `Thuế khoán ước tính` = `6.750đ`. Đối chiếu:
  `curl -s "$B/api/dashboard?date=$D" -H "$H"` → `revenue: 450000, receivable: 450000,
  collected: 0, draftCount: 0`; `curl -s $B/api/events/$EV -H "$H"` → `status: "CONFIRMED"`,
  `counterparty: "chị Lan"`, `paymentStatus: "UNPAID"`.
- **Từ chối một bản nháp khác.** Lặp mở màn + gửi với `text "Mua băng keo 60 nghìn tiền mặt"`
  → Event Detail `Loại` = `PURCHASE`; `tap` nút `Từ chối`. Về Home, `Chi phí` vẫn `0đ`.
  Home → `Giao dịch` → tab `Nháp` trống; tab `Tất cả` có thẻ 60.000đ với chip `REJECTED`.
  Đối chiếu: `curl -s "$B/api/events?status=REJECTED" -H "$H"` có event `amount: 60000`.
- **Bằng chứng.** `screenshot` Home và tab `Nháp`; `inspect` Home đọc text card `Doanh thu`.
  Kèm output hai lệnh `curl` dashboard và events ở trên.
