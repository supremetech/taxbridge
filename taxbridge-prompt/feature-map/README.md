# App Feature Map

Kịch bản kiểm chứng end-to-end theo feature, dùng **sau khi code** để đóng vòng: người
dùng làm gì → lệnh nào tái hiện được → bằng chứng quan sát được là gì. Đọc mục lục trước,
rồi dùng file feature tương ứng làm kịch bản.

Vai trò so với tài liệu khác (`CLAUDE.md` §3):

- **Không** định nghĩa DTO / endpoint / status code — đó là `contract/`; ở đây chỉ link.
- **Không** mô tả layout màn hình — đó là plan Flutter §6. Nhưng bảng `Handles` ở đây
  **sở hữu** nhãn nút / ô nhập / chip; plan Flutter và code dùng đúng nhãn đó.
- v1 chỉ đào sâu hai luồng hero (7 UC còn lại: `contract/endpoints.md` "Thứ tự smoke 9 UC" +
  `tests/smoke/smoke.sh`). Phase 2 (`requirements-phase2.md`) có 5 file, mỗi yêu cầu một file.

## Harness thật

| Harness | Dùng cho | Cách gọi |
|---|---|---|
| `curl` | API — local `flask run --port 8787`, ngrok, hoặc Functions | mẫu ở `contract/endpoints.md`; `B` = base URL, `T` = token từ `POST /api/login` |
| iOS Simulator (tool `control` của Claude Code) | App chạy trên Simulator với `--dart-define=API_BASE_URL=http://localhost:8787 --dart-define=DEMO=true` | `inspect` tìm element theo `marker` = nhãn (khớp substring, nên emoji đầu nút Home không ảnh hưởng), `tap` vào tâm `frame`, `text` gõ, `screenshot` lấy bằng chứng |

Simulator không có camera / mic: luồng ảnh và voice dùng nút **Dùng file demo**
(`DEMO=true`). Trên iPhone thật làm tay theo cùng kịch bản.

## Quy ước cho một file feature

Mỗi file bắt đầu bằng H1 và một đoạn mô tả hành vi hiển thị với người dùng, rồi đúng
bốn mục H2 theo thứ tự:

1. `Sub-features` — ID ngắn, mỗi hành vi một dòng.
2. `How to get to it (user POV)` — mọi điểm vào của người dùng, gọi bằng nhãn trên màn hình.
3. `Handles` — bảng nhãn ổn định (màn hình · loại · nhãn); nơi duy nhất định nghĩa nhãn.
4. `Driving it with <harness>` — bắt đầu bằng `Preconditions:`, rồi các gạch đầu dòng có
   nhãn đậm, mỗi gạch = một hành động người dùng + lệnh cụ thể + kết quả quan sát được.

Không đưa chi tiết implementation vào đây.

## Features

- [Capture a sale by text and confirm the draft](./capture-confirm-sale.md) — UC2: gõ một
  câu bán hàng, sửa bản nháp AI, xác nhận / từ chối, Home làm mới. Harness: Simulator, có
  `curl` đối chiếu.
- [Match or classify incoming money](./match-classify-money.md) — UC4 + UC5 (hero): tiền
  vào từ ảnh chuyển khoản, ghép với đơn đã xác nhận, hoặc phân loại đặt cọc mà doanh thu
  không đổi. Harness: `curl`, đối chiếu trên app ở bước cuối.

### Phase 2 (12/09 chiều, `requirements-phase2.md`)

- [Ghi nhận theo ngày trên chứng từ và Home theo ngày](./doc-date-home.md) — ② UC10: ảnh in
  11/09 vào sổ 11/09, sổ đã đóng tự cập nhật, Home lật ngày, hero giữ nguyên. Harness: `curl` + Simulator.
- [Bot trả lời trong Zalo](./zalo-reply.md) — ⑤ UC11: 5 mẫu câu trả lời. Harness: `curl` + điện thoại thật.
- [Báo cáo theo khoảng thời gian](./report-range.md) — ④ UC12: preset, theo ngày, theo loại. Harness: `curl` + Simulator.
- [Tồn đọng và tin nhắn Zalo cũ](./pending-backlog.md) — ③ UC13: cảnh báo Home, màn Tồn đọng, replay
  sau register. Harness: `curl` + Simulator.
- [Đối soát lịch sử chuyển khoản](./bank-history-reconcile.md) — ① UC14: batch + dedupe + màn Đối soát.
  Harness: `curl` + Simulator.
