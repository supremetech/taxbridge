# Back-end test — 2026-09-12-phase2

Base: `https://asia-southeast1-hackathon-42790.cloudfunctions.net/api` · chạy lúc 2026-09-12T13:33:37+07:00

## 1. Độ hiệu quả xử lý back-end

**Điểm sức khỏe: 100/100** (trọng số critical ×3 · major ×2 · minor ×1)

| Chỉ số | Giá trị |
|---|---|
| Độ chính xác xử lý (assertion, đã loại BLOCKED) | 1.0 |
| Rule critical bị vi phạm | 0 |
| Rule ảnh hưởng HERO bị vi phạm | 0 |
| Tự ghép khi không được phép | 0 (phải = 0) |
| Phân loại tiền làm đổi doanh thu | 0 (phải = 0) |
| Chuyển trạng thái trái phép mà vẫn thành công | 0 (phải = 0) |
| Assertion về tiền khớp tuyệt đối | 1.0 |
| Variation BLOCKED vì AI seed hỏng | 0.0 (không tính vào điểm) |
| Độ phủ rule | 44/45 |

**Trọng số thực tế giải ngược từ score quan sát:** `w_amount=0.6 · w_name=0.3 · w_day=0.1` — spec: `0.6 / 0.3 / 0.1`.

## 2. Sẵn sàng cho demo (theo use case §9)

| UC | Trạng thái | Chi tiết |
|---|---|---|
| UC1 | ✅ READY | 1 đạt · 0 sai · 0 blocked |
| UC10 | ✅ READY | 3 đạt · 0 sai · 0 blocked |
| UC12 | ✅ READY | 2 đạt · 0 sai · 0 blocked |
| UC13 | ✅ READY | 1 đạt · 0 sai · 0 blocked |
| UC14 | ✅ READY | 4 đạt · 0 sai · 0 blocked |
| UC2 | ✅ READY | 3 đạt · 0 sai · 0 blocked |
| UC4 | ✅ READY | 10 đạt · 0 sai · 0 blocked |
| UC5 | ✅ READY | 8 đạt · 0 sai · 0 blocked |
| UC6 | ✅ READY | 1 đạt · 0 sai · 0 blocked |
| UC7 | ✅ READY | 4 đạt · 0 sai · 0 blocked |

## 3. Theo nhóm rule

| Nhóm | Assertion đạt/tổng | % |
|---|---|---|
| batch | 17/17 | 100% |
| closeday | 42/42 | 100% |
| dashboard | 58/58 | 100% |
| date | 9/9 | 100% |
| errors | 20/20 | 100% |
| events | 394/394 | 100% |
| matching | 39/39 | 100% |
| money | 36/36 | 100% |
| pending | 8/8 | 100% |
| report | 25/25 | 100% |

## 4. Theo scenario / variation

| Variation | KQ | Assertion | Ghi chú |
|---|---|---|---|
| `SC-CAND/V1-weights` | ✅ PASS | 31/31 |  |
| `SC-CAND/V2-threshold` | ✅ PASS | 26/26 |  |
| `SC-CAND/V3-pool-filter` | ✅ PASS | 66/66 |  |
| `SC-CAND/V4-hero-no-candidate` | ✅ PASS | 13/13 |  |
| `SC-CAND/V5-ambiguous-two-candidates` | ✅ PASS | 21/21 |  |
| `SC-CAND/P1-name-normalize` | 🔎 PROBE | 23/23 |  |
| `SC-HERO/V1-match-effects` | ✅ PASS | 23/23 |  |
| `SC-HERO/V2-classify-deposit` | ✅ PASS | 17/17 |  |
| `SC-HERO/V3-classify-owner-money` | ✅ PASS | 12/12 |  |
| `SC-HERO/V4-bankin-all-status` | ✅ PASS | 16/16 |  |
| `SC-HERO/V5-state-guards` | ✅ PASS | 17/17 |  |
| `SC-HERO/V6-invalid-input` | ✅ PASS | 10/10 |  |
| `SC-HERO/P2-match-target` | 🔎 PROBE | 25/25 |  |
| `SC-CLOSE/V1-generate-and-resolve` | ✅ PASS | 52/52 |  |
| `SC-CLOSE/V2-classify-keeps-summary` | ✅ PASS | 13/13 |  |
| `SC-CLOSE/V3-reclose-upsert` | ✅ PASS | 19/19 |  |
| `SC-CLOSE/V4-history-and-errors` | ✅ PASS | 28/28 |  |
| `SC-DASH/V1-formula` | ✅ PASS | 82/82 |  |
| `SC-DASH/V2-date-filter` | ✅ PASS | 26/26 |  |
| `SC-DASH/V3-empty-business` | ✅ PASS | 10/10 |  |
| `SC-DATE/V1-image-date-wins` | ✅ PASS | 9/9 |  |
| `SC-DATE/V2-text-without-date-is-today` | ✅ PASS | 3/3 |  |
| `SC-DATE/P3-text-with-date` | 🔎 PROBE | 1/1 |  |
| `SC-REPORT/V1-report-totals` | ✅ PASS | 50/50 |  |
| `SC-REPORT/V2-report-validation` | ✅ PASS | 6/6 |  |
| `SC-REPORT/V3-pending-all-days` | ✅ PASS | 29/29 |  |
| `SC-BATCH/V1-batch-and-dedupe` | ✅ PASS | 9/9 |  |
| `SC-BATCH/V2-reject-single-receipt` | ✅ PASS | 5/5 |  |
| `SC-BATCH/V3-batch-then-single` | ✅ PASS | 4/4 |  |
| `SC-BATCH/V4-out-direction-not-in-bankin` | ✅ PASS | 2/2 |  |

## 5. Chi tiết sai, gom theo rule

Không có assertion nào sai.
## 6. Hành vi chưa định nghĩa (probe — không tính pass/fail)

### `SC-CAND/P1-name-normalize`

- Câu hỏi: similar() so token BẰNG hay so CHỨA? Có bỏ dấu, bỏ hoa/thường, bỏ tiền tố (chị/anh/o) không?
- Ảnh hưởng: Nếu không bỏ dấu thì mọi so tên đều trượt, điểm kẹt ở 0.7 và thứ tự candidate sai khi có nhiều đơn cùng mệnh giá.
- Quan sát `mov.candidates[*].eventId` = `["ev_5cfb543b2d13", "ev_974170864e43", "ev_b10bbcee7ea2"]`
- Quan sát `mov.candidates[*].score` = `[1.0, 1.0, 0.7]`

### `SC-HERO/P2-match-target`

- Câu hỏi: Spec không định nghĩa: match vào event DRAFT / PURCHASE / đã PAID được chấp nhận hay 409? Mỗi target dùng MỘT movement riêng, nếu không thì lệnh thứ hai sẽ nhận 409 vì movement đã MATCHED chứ không phải vì backend chặn target.
- Ảnh hưởng: Match vào event DRAFT ⇒ đơn thành DRAFT + PAID: không vào doanh thu nhưng đã coi như thu tiền, và warning DRAFT_EVENT vẫn treo. Match vào event đã PAID ⇒ hai khoản tiền cùng trỏ một đơn, collected chỉ tăng một lần.
- Quan sát `mDraft.status` = `"MATCHED"`
- Quan sát `mPurchase.status` = `"MATCHED"`
- Quan sát `mPaid.status` = `"MATCHED"`
- Quan sát `evDraftAfter.status` = `"DRAFT"`
- Quan sát `evDraftAfter.paymentStatus` = `"PAID"`
- Quan sát `dashAfter.revenue` = `250000`
- Quan sát `dashAfter.collected` = `250000`

### `SC-DATE/P3-text-with-date`

- Câu hỏi: Câu 'Hôm qua bán ...' có ra occurredAt = hôm qua không, và resolve_occurred_at có kẹp đúng khoảng [now−365d, now+1d] không?
- Ảnh hưởng: Quy đổi sai thì giao dịch rơi sang ngày khác, sổ ngày đã đóng bị lệch. Phần đọc ngày là do AI nên chỉ ghi nhận, không chấm.
- Quan sát `ev.occurredAt` = `"2026-09-11T12:00:00+07:00"`
- Quan sát `cap.occurredAt` = `"2026-09-11T12:00:00+07:00"`

## 7. Độ trễ

| Endpoint | Gọi AI | n | p50 | p95 | max |
|---|---|---|---|---|---|
| `GET /api/daily-records` | — | 2 | 230ms | 232ms | 232ms |
| `GET /api/daily-records/2026-09-07` | — | 1 | 218ms | 218ms | 218ms |
| `GET /api/daily-records/2026-09-11` | — | 4 | 230ms | 239ms | 239ms |
| `GET /api/dashboard` | — | 32 | 249ms | 357ms | 465ms |
| `GET /api/events` | — | 8 | 231ms | 269ms | 269ms |
| `GET /api/events/ev_39ffb8dbda3d` | — | 1 | 211ms | 211ms | 211ms |
| `GET /api/events/ev_5fb5a0ac5536` | — | 1 | 243ms | 243ms | 243ms |
| `GET /api/events/ev_ce6395390747` | — | 1 | 236ms | 236ms | 236ms |
| `GET /api/events/ev_dc6e94487ad1` | — | 1 | 234ms | 234ms | 234ms |
| `GET /api/money-movements` | — | 6 | 237ms | 285ms | 285ms |
| `GET /api/money-movements/mov_07ac6fe04854` | — | 2 | 239ms | 240ms | 240ms |
| `GET /api/money-movements/mov_0bf4b96c4740` | — | 2 | 235ms | 240ms | 240ms |
| `GET /api/money-movements/mov_2de4aa057d14` | — | 1 | 249ms | 249ms | 249ms |
| `GET /api/money-movements/mov_2fd350082450` | — | 2 | 237ms | 244ms | 244ms |
| `GET /api/money-movements/mov_49a8b3fd033b` | — | 2 | 243ms | 249ms | 249ms |
| `GET /api/money-movements/mov_4ae99d1d133e` | — | 1 | 240ms | 240ms | 240ms |
| `GET /api/money-movements/mov_55a1275316fe` | — | 1 | 237ms | 237ms | 237ms |
| `GET /api/money-movements/mov_5fc7d435c1ae` | — | 1 | 237ms | 237ms | 237ms |
| `GET /api/money-movements/mov_933a4864abc5` | — | 2 | 244ms | 245ms | 245ms |
| `GET /api/money-movements/mov_952de9957457` | — | 1 | 251ms | 251ms | 251ms |
| `GET /api/money-movements/mov_9a753d1d199d` | — | 1 | 256ms | 256ms | 256ms |
| `GET /api/money-movements/mov_a8c5883e2242` | — | 3 | 251ms | 252ms | 252ms |
| `GET /api/money-movements/mov_bf2eb1d7b37e` | — | 1 | 230ms | 230ms | 230ms |
| `GET /api/money-movements/mov_e2214fa14922` | — | 2 | 276ms | 316ms | 316ms |
| `GET /api/money-movements/mov_ff2ad5578a27` | — | 1 | 219ms | 219ms | 219ms |
| `GET /api/money-movements/mov_khong_ton_tai` | — | 1 | 225ms | 225ms | 225ms |
| `GET /api/pending` | — | 2 | 273ms | 289ms | 289ms |
| `GET /api/reports` | — | 5 | 226ms | 245ms | 245ms |
| `POST /api/captures` | có | 91 | 1847ms | 3291ms | 8933ms |
| `POST /api/close-day` | — | 9 | 293ms | 483ms | 483ms |
| `POST /api/events/ev_028bb76e0321/confirm` | — | 1 | 254ms | 254ms | 254ms |
| `POST /api/events/ev_0664f00c12be/confirm` | — | 1 | 268ms | 268ms | 268ms |
| `POST /api/events/ev_0a57fbe39c21/confirm` | — | 1 | 249ms | 249ms | 249ms |
| `POST /api/events/ev_108bc4d9f9a3/confirm` | — | 1 | 251ms | 251ms | 251ms |
| `POST /api/events/ev_1b8f6ccaacc6/confirm` | — | 1 | 266ms | 266ms | 266ms |
| `POST /api/events/ev_1e0f731bd4fc/confirm` | — | 1 | 270ms | 270ms | 270ms |
| `POST /api/events/ev_2269e921c367/confirm` | — | 1 | 325ms | 325ms | 325ms |
| `POST /api/events/ev_23c45476e5ac/confirm` | — | 1 | 252ms | 252ms | 252ms |
| `POST /api/events/ev_24eb1b5f19dd/confirm` | — | 1 | 299ms | 299ms | 299ms |
| `POST /api/events/ev_3d7c0a5cdbe2/reject` | — | 1 | 239ms | 239ms | 239ms |
| `POST /api/events/ev_3ef03e659308/confirm` | — | 1 | 255ms | 255ms | 255ms |
| `POST /api/events/ev_40885e5ef722/confirm` | — | 1 | 246ms | 246ms | 246ms |
| `POST /api/events/ev_445753c24071/confirm` | — | 1 | 243ms | 243ms | 243ms |
| `POST /api/events/ev_516339f8d3ae/confirm` | — | 1 | 269ms | 269ms | 269ms |
| `POST /api/events/ev_58d66e39b211/confirm` | — | 1 | 262ms | 262ms | 262ms |
| `POST /api/events/ev_5bb5eb1cc6af/confirm` | — | 1 | 270ms | 270ms | 270ms |
| `POST /api/events/ev_5cfb543b2d13/confirm` | — | 1 | 252ms | 252ms | 252ms |
| `POST /api/events/ev_5db87771d6b9/reject` | — | 1 | 298ms | 298ms | 298ms |
| `POST /api/events/ev_5f0e53bb28b5/reject` | — | 1 | 264ms | 264ms | 264ms |
| `POST /api/events/ev_638a11c62eb7/confirm` | — | 1 | 261ms | 261ms | 261ms |
| `POST /api/events/ev_66503c34a14c/confirm` | — | 1 | 259ms | 259ms | 259ms |
| `POST /api/events/ev_6861a64049f2/confirm` | — | 1 | 246ms | 246ms | 246ms |
| `POST /api/events/ev_691ac5ed460c/confirm` | — | 1 | 251ms | 251ms | 251ms |
| `POST /api/events/ev_7044b666777a/confirm` | — | 1 | 260ms | 260ms | 260ms |
| `POST /api/events/ev_84bbfbe6eca8/confirm` | — | 1 | 269ms | 269ms | 269ms |
| `POST /api/events/ev_95fd9f2e4c1a/confirm` | — | 1 | 258ms | 258ms | 258ms |
| `POST /api/events/ev_9616ec1dc879/confirm` | — | 1 | 251ms | 251ms | 251ms |
| `POST /api/events/ev_974170864e43/confirm` | — | 1 | 265ms | 265ms | 265ms |
| `POST /api/events/ev_a2166cf1d4df/confirm` | — | 1 | 251ms | 251ms | 251ms |
| `POST /api/events/ev_a3f79f5322e7/confirm` | — | 1 | 477ms | 477ms | 477ms |
| `POST /api/events/ev_a643d1f6036f/confirm` | — | 1 | 260ms | 260ms | 260ms |
| `POST /api/events/ev_acc8c28a6583/confirm` | — | 1 | 267ms | 267ms | 267ms |
| `POST /api/events/ev_b10800a54a12/confirm` | — | 1 | 245ms | 245ms | 245ms |
| `POST /api/events/ev_b10bbcee7ea2/confirm` | — | 1 | 263ms | 263ms | 263ms |
| `POST /api/events/ev_b1d91fc5cfb9/confirm` | — | 1 | 291ms | 291ms | 291ms |
| `POST /api/events/ev_b572e5a13993/confirm` | — | 1 | 242ms | 242ms | 242ms |
| `POST /api/events/ev_ba61cfc15d63/confirm` | — | 1 | 271ms | 271ms | 271ms |
| `POST /api/events/ev_bbc2c552b43c/confirm` | — | 1 | 263ms | 263ms | 263ms |
| `POST /api/events/ev_caaed4a65b3a/confirm` | — | 1 | 246ms | 246ms | 246ms |
| `POST /api/events/ev_ce6395390747/confirm` | — | 1 | 251ms | 251ms | 251ms |
| `POST /api/events/ev_d0964d1c6d9e/confirm` | — | 1 | 248ms | 248ms | 248ms |
| `POST /api/events/ev_d256a05aef38/confirm` | — | 1 | 345ms | 345ms | 345ms |
| `POST /api/events/ev_e227115a8008/confirm` | — | 1 | 253ms | 253ms | 253ms |
| `POST /api/events/ev_e712a1ad5943/confirm` | — | 1 | 261ms | 261ms | 261ms |
| `POST /api/events/ev_edd0e262dc37/confirm` | — | 1 | 253ms | 253ms | 253ms |
| `POST /api/events/ev_f0dd31cd5ef8/reject` | — | 1 | 254ms | 254ms | 254ms |
| `POST /api/events/ev_f10a9eca1576/confirm` | — | 1 | 262ms | 262ms | 262ms |
| `POST /api/events/ev_f2a498f2643f/confirm` | — | 1 | 262ms | 262ms | 262ms |
| `POST /api/events/ev_f2b824e784a1/confirm` | — | 1 | 278ms | 278ms | 278ms |
| `POST /api/events/ev_f8169b770ec7/confirm` | — | 1 | 259ms | 259ms | 259ms |
| `POST /api/events/ev_f8c992c3bc61/confirm` | — | 1 | 252ms | 252ms | 252ms |
| `POST /api/events/ev_f925ca727a37/confirm` | — | 1 | 250ms | 250ms | 250ms |
| `POST /api/events/ev_ff91bc41977b/confirm` | — | 1 | 256ms | 256ms | 256ms |
| `POST /api/money-movements/mov_2de4aa057d14/classify` | — | 3 | 226ms | 239ms | 239ms |
| `POST /api/money-movements/mov_2de4aa057d14/match` | — | 2 | 224ms | 233ms | 233ms |
| `POST /api/money-movements/mov_4a5bee7455aa/match` | — | 1 | 276ms | 276ms | 276ms |
| `POST /api/money-movements/mov_4ae99d1d133e/match` | — | 1 | 290ms | 290ms | 290ms |
| `POST /api/money-movements/mov_5f49da72e616/classify` | — | 1 | 303ms | 303ms | 303ms |
| `POST /api/money-movements/mov_5fc7d435c1ae/match` | — | 1 | 320ms | 320ms | 320ms |
| `POST /api/money-movements/mov_83e7e2ca1e77/match` | — | 1 | 267ms | 267ms | 267ms |
| `POST /api/money-movements/mov_8825d3c268d0/classify` | — | 1 | 266ms | 266ms | 266ms |
| `POST /api/money-movements/mov_952de9957457/match` | — | 1 | 335ms | 335ms | 335ms |
| `POST /api/money-movements/mov_9a753d1d199d/classify` | — | 1 | 260ms | 260ms | 260ms |
| `POST /api/money-movements/mov_b0d8102be65a/match` | — | 1 | 267ms | 267ms | 267ms |
| `POST /api/money-movements/mov_cc446ee348a9/classify` | — | 1 | 251ms | 251ms | 251ms |
| `POST /api/money-movements/mov_de24df87e204/classify` | — | 1 | 271ms | 271ms | 271ms |
| `POST /api/money-movements/mov_e2214fa14922/classify` | — | 1 | 230ms | 230ms | 230ms |
| `POST /api/money-movements/mov_e2214fa14922/match` | — | 2 | 248ms | 264ms | 264ms |
| `POST /api/money-movements/mov_ff2ad5578a27/classify` | — | 2 | 241ms | 246ms | 246ms |
| `POST /api/money-movements/mov_ff2ad5578a27/match` | — | 1 | 242ms | 242ms | 242ms |
| `POST /api/register` | — | 30 | 433ms | 504ms | 505ms |
| `PUT /api/events/ev_028bb76e0321` | — | 1 | 247ms | 247ms | 247ms |
| `PUT /api/events/ev_0664f00c12be` | — | 1 | 258ms | 258ms | 258ms |
| `PUT /api/events/ev_0a57fbe39c21` | — | 1 | 240ms | 240ms | 240ms |
| `PUT /api/events/ev_108bc4d9f9a3` | — | 1 | 280ms | 280ms | 280ms |
| `PUT /api/events/ev_1b8f6ccaacc6` | — | 1 | 269ms | 269ms | 269ms |
| `PUT /api/events/ev_1e0f731bd4fc` | — | 1 | 265ms | 265ms | 265ms |
| `PUT /api/events/ev_2269e921c367` | — | 1 | 239ms | 239ms | 239ms |
| `PUT /api/events/ev_23c45476e5ac` | — | 1 | 255ms | 255ms | 255ms |
| `PUT /api/events/ev_24eb1b5f19dd` | — | 1 | 264ms | 264ms | 264ms |
| `PUT /api/events/ev_3cc04e47b448` | — | 1 | 304ms | 304ms | 304ms |
| `PUT /api/events/ev_3d7c0a5cdbe2` | — | 1 | 255ms | 255ms | 255ms |
| `PUT /api/events/ev_3ef03e659308` | — | 1 | 257ms | 257ms | 257ms |
| `PUT /api/events/ev_40885e5ef722` | — | 1 | 266ms | 266ms | 266ms |
| `PUT /api/events/ev_445753c24071` | — | 1 | 257ms | 257ms | 257ms |
| `PUT /api/events/ev_4d5581cc403a` | — | 1 | 266ms | 266ms | 266ms |
| `PUT /api/events/ev_516339f8d3ae` | — | 1 | 266ms | 266ms | 266ms |
| `PUT /api/events/ev_58d66e39b211` | — | 1 | 290ms | 290ms | 290ms |
| `PUT /api/events/ev_5bb5eb1cc6af` | — | 1 | 256ms | 256ms | 256ms |
| `PUT /api/events/ev_5cfb543b2d13` | — | 1 | 264ms | 264ms | 264ms |
| `PUT /api/events/ev_5db87771d6b9` | — | 1 | 265ms | 265ms | 265ms |
| `PUT /api/events/ev_5f0e53bb28b5` | — | 1 | 260ms | 260ms | 260ms |
| `PUT /api/events/ev_5fb5a0ac5536` | — | 1 | 276ms | 276ms | 276ms |
| `PUT /api/events/ev_638a11c62eb7` | — | 1 | 269ms | 269ms | 269ms |
| `PUT /api/events/ev_66503c34a14c` | — | 1 | 265ms | 265ms | 265ms |
| `PUT /api/events/ev_6861a64049f2` | — | 1 | 250ms | 250ms | 250ms |
| `PUT /api/events/ev_691ac5ed460c` | — | 1 | 273ms | 273ms | 273ms |
| `PUT /api/events/ev_69d3a3142ef8` | — | 1 | 266ms | 266ms | 266ms |
| `PUT /api/events/ev_7044b666777a` | — | 1 | 311ms | 311ms | 311ms |
| `PUT /api/events/ev_84bbfbe6eca8` | — | 1 | 265ms | 265ms | 265ms |
| `PUT /api/events/ev_95fd9f2e4c1a` | — | 1 | 263ms | 263ms | 263ms |
| `PUT /api/events/ev_9616ec1dc879` | — | 1 | 252ms | 252ms | 252ms |
| `PUT /api/events/ev_974170864e43` | — | 1 | 269ms | 269ms | 269ms |
| `PUT /api/events/ev_97d4ed78cad7` | — | 1 | 247ms | 247ms | 247ms |
| `PUT /api/events/ev_97e15e74739d` | — | 1 | 236ms | 236ms | 236ms |
| `PUT /api/events/ev_a2166cf1d4df` | — | 1 | 242ms | 242ms | 242ms |
| `PUT /api/events/ev_a3f79f5322e7` | — | 1 | 253ms | 253ms | 253ms |
| `PUT /api/events/ev_a643d1f6036f` | — | 1 | 270ms | 270ms | 270ms |
| `PUT /api/events/ev_acc8c28a6583` | — | 1 | 305ms | 305ms | 305ms |
| `PUT /api/events/ev_b10800a54a12` | — | 1 | 269ms | 269ms | 269ms |
| `PUT /api/events/ev_b10bbcee7ea2` | — | 1 | 268ms | 268ms | 268ms |
| `PUT /api/events/ev_b1d91fc5cfb9` | — | 1 | 247ms | 247ms | 247ms |
| `PUT /api/events/ev_b572e5a13993` | — | 1 | 259ms | 259ms | 259ms |
| `PUT /api/events/ev_ba61cfc15d63` | — | 1 | 291ms | 291ms | 291ms |
| `PUT /api/events/ev_bbc2c552b43c` | — | 1 | 266ms | 266ms | 266ms |
| `PUT /api/events/ev_c477ac4b83ea` | — | 1 | 273ms | 273ms | 273ms |
| `PUT /api/events/ev_caaed4a65b3a` | — | 1 | 254ms | 254ms | 254ms |
| `PUT /api/events/ev_ce6395390747` | — | 1 | 253ms | 253ms | 253ms |
| `PUT /api/events/ev_d0964d1c6d9e` | — | 1 | 259ms | 259ms | 259ms |
| `PUT /api/events/ev_d256a05aef38` | — | 1 | 252ms | 252ms | 252ms |
| `PUT /api/events/ev_e227115a8008` | — | 1 | 252ms | 252ms | 252ms |
| `PUT /api/events/ev_e712a1ad5943` | — | 1 | 256ms | 256ms | 256ms |
| `PUT /api/events/ev_edd0e262dc37` | — | 1 | 289ms | 289ms | 289ms |
| `PUT /api/events/ev_f0dd31cd5ef8` | — | 1 | 257ms | 257ms | 257ms |
| `PUT /api/events/ev_f10a9eca1576` | — | 1 | 275ms | 275ms | 275ms |
| `PUT /api/events/ev_f2a498f2643f` | — | 1 | 275ms | 275ms | 275ms |
| `PUT /api/events/ev_f2b824e784a1` | — | 1 | 272ms | 272ms | 272ms |
| `PUT /api/events/ev_f8169b770ec7` | — | 1 | 280ms | 280ms | 280ms |
| `PUT /api/events/ev_f8c992c3bc61` | — | 1 | 246ms | 246ms | 246ms |
| `PUT /api/events/ev_f925ca727a37` | — | 1 | 254ms | 254ms | 254ms |
| `PUT /api/events/ev_ff91bc41977b` | — | 1 | 257ms | 257ms | 257ms |
