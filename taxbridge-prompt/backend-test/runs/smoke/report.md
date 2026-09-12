# Back-end test — smoke

Base: `https://asia-southeast1-hackathon-42790.cloudfunctions.net/api` · chạy lúc 2026-09-12T12:40:02+07:00

## 1. Độ hiệu quả xử lý back-end

**Điểm sức khỏe: 99/100** (trọng số critical ×3 · major ×2 · minor ×1)

| Chỉ số | Giá trị |
|---|---|
| Độ chính xác xử lý (assertion, đã loại BLOCKED) | 0.9915 |
| Rule critical bị vi phạm | 1 |
| Rule ảnh hưởng HERO bị vi phạm | 1 |
| Tự ghép khi không được phép | 0 (phải = 0) |
| Phân loại tiền làm đổi doanh thu | 0 (phải = 0) |
| Chuyển trạng thái trái phép mà vẫn thành công | 0 (phải = 0) |
| Assertion về tiền khớp tuyệt đối | 0.9762 |
| Variation BLOCKED vì AI seed hỏng | 0.0 (không tính vào điểm) |
| Độ phủ rule | 10/31 |

## 2. Sẵn sàng cho demo (theo use case §9)

| UC | Trạng thái | Chi tiết |
|---|---|---|
| UC1 | ✅ READY | 1 đạt · 0 sai · 0 blocked |
| UC2 | ❌ BROKEN | 1 đạt · 1 sai · 0 blocked |
| UC6 | ❌ BROKEN | 0 đạt · 1 sai · 0 blocked |

## 3. Theo nhóm rule

| Nhóm | Assertion đạt/tổng | % |
|---|---|---|
| dashboard | 27/28 | 96% |
| errors | 2/2 | 100% |
| events | 87/87 | 100% |

## 4. Theo scenario / variation

| Variation | KQ | Assertion | Ghi chú |
|---|---|---|---|
| `SC-DASH/V1-formula` | ❌ FAIL | 80/81 |  |
| `SC-DASH/V2-date-filter` | ✅ PASS | 26/26 |  |
| `SC-DASH/V3-empty-business` | ✅ PASS | 10/10 |  |

## 5. Chi tiết sai, gom theo rule

### `DASH-RECEIVABLE` — critical · **HERO**

- Rule: receivable = revenue − collected.
- Nguồn: `implement-plan-backend-poc.md §7`
- `SC-DASH/V1-formula` — `dash2.receivable` eq `1699000` → thực tế `700000`

## 6. Hành vi chưa định nghĩa (probe — không tính pass/fail)

### `SC-CAND/P1-name-normalize`

- Câu hỏi: similar() so token BẰNG hay so CHỨA? Có bỏ dấu, bỏ hoa/thường, bỏ tiền tố (chị/anh/o) không?
- Ảnh hưởng: Nếu không bỏ dấu thì mọi so tên đều trượt, điểm kẹt ở 0.7 và thứ tự candidate sai khi có nhiều đơn cùng mệnh giá.
- Quan sát `mov.candidates[*].eventId` = `null`
- Quan sát `mov.candidates[*].score` = `null`

### `SC-HERO/P2-match-target`

- Câu hỏi: Spec không định nghĩa: match vào event DRAFT / PURCHASE / đã PAID được chấp nhận hay 409?
- Ảnh hưởng: Nếu match vào event đã PAID trả 200 thì hai khoản tiền cùng trỏ một đơn: collected chỉ tăng một lần, tiền thật bị mất dấu.
- Quan sát `mDraft.status` = `null`
- Quan sát `mPurchase.status` = `null`
- Quan sát `mPaid.status` = `null`

## 7. Độ trễ

| Endpoint | Gọi AI | n | p50 | p95 | max |
|---|---|---|---|---|---|
| `GET /api/dashboard` | — | 9 | 268ms | 308ms | 308ms |
| `GET /api/events` | — | 2 | 328ms | 349ms | 349ms |
| `GET /api/money-movements` | — | 1 | 236ms | 236ms | 236ms |
| `POST /api/captures` | có | 14 | 1899ms | 3038ms | 3038ms |
| `POST /api/events/ev_23673229ce08/confirm` | — | 1 | 274ms | 274ms | 274ms |
| `POST /api/events/ev_5c9d88e53f53/confirm` | — | 1 | 307ms | 307ms | 307ms |
| `POST /api/events/ev_6d36ca262a10/confirm` | — | 1 | 305ms | 305ms | 305ms |
| `POST /api/events/ev_81ee109443a8/confirm` | — | 1 | 266ms | 266ms | 266ms |
| `POST /api/events/ev_8428698ecee8/confirm` | — | 1 | 268ms | 268ms | 268ms |
| `POST /api/events/ev_b67a98f2ba56/confirm` | — | 1 | 362ms | 362ms | 362ms |
| `POST /api/events/ev_b6b7f3b2071e/reject` | — | 1 | 269ms | 269ms | 269ms |
| `POST /api/events/ev_b7023e3afcca/confirm` | — | 1 | 317ms | 317ms | 317ms |
| `POST /api/events/ev_c23db325a861/confirm` | — | 1 | 289ms | 289ms | 289ms |
| `POST /api/events/ev_e197a1dd5778/confirm` | — | 1 | 285ms | 285ms | 285ms |
| `POST /api/events/ev_e1ba3847cda5/confirm` | — | 1 | 260ms | 260ms | 260ms |
| `POST /api/events/ev_e6f0a0dcc4a2/reject` | — | 1 | 297ms | 297ms | 297ms |
| `POST /api/events/ev_eba3b46d9b17/confirm` | — | 1 | 279ms | 279ms | 279ms |
| `POST /api/register` | — | 3 | 499ms | 728ms | 728ms |
| `PUT /api/events/ev_23673229ce08` | — | 1 | 257ms | 257ms | 257ms |
| `PUT /api/events/ev_3282a0f00bb2` | — | 1 | 354ms | 354ms | 354ms |
| `PUT /api/events/ev_5c9d88e53f53` | — | 1 | 251ms | 251ms | 251ms |
| `PUT /api/events/ev_6d36ca262a10` | — | 1 | 283ms | 283ms | 283ms |
| `PUT /api/events/ev_81ee109443a8` | — | 1 | 279ms | 279ms | 279ms |
| `PUT /api/events/ev_8428698ecee8` | — | 1 | 253ms | 253ms | 253ms |
| `PUT /api/events/ev_b67a98f2ba56` | — | 1 | 320ms | 320ms | 320ms |
| `PUT /api/events/ev_b6b7f3b2071e` | — | 1 | 280ms | 280ms | 280ms |
| `PUT /api/events/ev_b7023e3afcca` | — | 1 | 263ms | 263ms | 263ms |
| `PUT /api/events/ev_c23db325a861` | — | 1 | 242ms | 242ms | 242ms |
| `PUT /api/events/ev_e197a1dd5778` | — | 1 | 249ms | 249ms | 249ms |
| `PUT /api/events/ev_e1ba3847cda5` | — | 1 | 281ms | 281ms | 281ms |
| `PUT /api/events/ev_e6f0a0dcc4a2` | — | 1 | 247ms | 247ms | 247ms |
| `PUT /api/events/ev_eba3b46d9b17` | — | 1 | 256ms | 256ms | 256ms |
