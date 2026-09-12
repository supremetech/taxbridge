# Back-end test — 2026-09-12-baseline

Base: `https://asia-southeast1-hackathon-42790.cloudfunctions.net/api` · chạy lúc 2026-09-12T12:59:06+07:00

## 1. Độ hiệu quả xử lý back-end

**Điểm sức khỏe: 95/100** (trọng số critical ×3 · major ×2 · minor ×1)

| Chỉ số | Giá trị |
|---|---|
| Độ chính xác xử lý (assertion, đã loại BLOCKED) | 0.9528 |
| Rule critical bị vi phạm | 4 |
| Rule ảnh hưởng HERO bị vi phạm | 3 |
| Tự ghép khi không được phép | 0 (phải = 0) |
| Phân loại tiền làm đổi doanh thu | 2 (phải = 0) |
| Chuyển trạng thái trái phép mà vẫn thành công | 0 (phải = 0) |
| Assertion về tiền khớp tuyệt đối | 0.9174 |
| Variation BLOCKED vì AI seed hỏng | 0.0 (không tính vào điểm) |
| Độ phủ rule | 31/31 |

**Trọng số thực tế giải ngược từ score quan sát:** `w_amount=0.6 · w_name=0.3 · w_day=0.1` — spec: `0.6 / 0.3 / 0.1`.

## 2. Sẵn sàng cho demo (theo use case §9)

| UC | Trạng thái | Chi tiết |
|---|---|---|
| UC1 | ✅ READY | 1 đạt · 0 sai · 0 blocked |
| UC2 | ✅ READY | 2 đạt · 0 sai · 0 blocked |
| UC4 | ❌ BROKEN | 7 đạt · 3 sai · 0 blocked |
| UC5 | ❌ BROKEN | 3 đạt · 5 sai · 0 blocked |
| UC6 | ✅ READY | 1 đạt · 0 sai · 0 blocked |
| UC7 | ❌ BROKEN | 1 đạt · 3 sai · 0 blocked |

## 3. Theo nhóm rule

| Nhóm | Assertion đạt/tổng | % |
|---|---|---|
| closeday | 31/42 | 74% |
| dashboard | 38/48 | 79% |
| errors | 19/19 | 100% |
| events | 346/346 | 100% |
| matching | 37/39 | 95% |
| money | 34/36 | 94% |

## 4. Theo scenario / variation

| Variation | KQ | Assertion | Ghi chú |
|---|---|---|---|
| `SC-CAND/V1-weights` | ✅ PASS | 31/31 |  |
| `SC-CAND/V2-threshold` | ✅ PASS | 26/26 |  |
| `SC-CAND/V3-pool-filter` | ✅ PASS | 66/66 |  |
| `SC-CAND/V4-hero-no-candidate` | ❌ FAIL | 11/13 |  |
| `SC-CAND/V5-ambiguous-two-candidates` | ❌ FAIL | 19/21 |  |
| `SC-CAND/P1-name-normalize` | 🔎 PROBE | 23/23 |  |
| `SC-HERO/V1-match-effects` | ❌ FAIL | 22/23 |  |
| `SC-HERO/V2-classify-deposit` | ❌ FAIL | 15/17 |  |
| `SC-HERO/V3-classify-owner-money` | ❌ FAIL | 10/12 |  |
| `SC-HERO/V4-bankin-all-status` | ❌ FAIL | 11/16 |  |
| `SC-HERO/V5-state-guards` | ✅ PASS | 17/17 |  |
| `SC-HERO/V6-invalid-input` | ✅ PASS | 10/10 |  |
| `SC-HERO/P2-match-target` | 🔎 PROBE | 25/25 |  |
| `SC-CLOSE/V1-generate-and-resolve` | ❌ FAIL | 46/52 |  |
| `SC-CLOSE/V2-classify-keeps-summary` | ❌ FAIL | 11/13 |  |
| `SC-CLOSE/V3-reclose-upsert` | ❌ FAIL | 16/19 |  |
| `SC-CLOSE/V4-history-and-errors` | ✅ PASS | 28/28 |  |
| `SC-DASH/V1-formula` | ✅ PASS | 82/82 |  |
| `SC-DASH/V2-date-filter` | ✅ PASS | 26/26 |  |
| `SC-DASH/V3-empty-business` | ✅ PASS | 10/10 |  |

## 5. Chi tiết sai, gom theo rule

### `CAND-SCORE-FORMULA` — critical · **HERO**

- Rule: score = 0.6·(amount bằng nhau) + 0.3·(similar tên/memo) + 0.1·(cùng ngày)
- Nguồn: `implement-plan-backend-poc.md §6`
- `SC-CAND/V5-ambiguous-two-candidates` — `mov.candidates[?eventId=ev_445b6579a8b1].score` approx `0.7` → thực tế `0.6`
- `SC-CAND/V5-ambiguous-two-candidates` — `mov.candidates[?eventId=ev_99c10e328d1d].score` approx `0.7` → thực tế `0.6`

### `CLOSE-COUNT-OPEN-ONLY` — major

- Rule: warningCount = số warning OPEN.
- Nguồn: `implement-plan-backend-poc.md §8`
- `SC-CLOSE/V1-generate-and-resolve` — `close1.warningCount` eq `3` → thực tế `2`
- `SC-CLOSE/V1-generate-and-resolve` — `rec1.warningCount` eq `2` → thực tế `1`
- `SC-CLOSE/V1-generate-and-resolve` — `rec2.warningCount` eq `1` → thực tế `0`
- `SC-CLOSE/V2-classify-keeps-summary` — `close1.warningCount` eq `1` → thực tế `0`
- `SC-CLOSE/V3-reclose-upsert` — `close2.warningCount` eq `2` → thực tế `1`

### `CLOSE-RESOLVE` — critical

- Rule: Sau confirm/reject/match/classify: warning OPEN trùng resourceId → RESOLVED + resolvedAt, recompute summary.
- Nguồn: `implement-plan-backend-poc.md §8`
- `SC-CLOSE/V1-generate-and-resolve` — `rec3.warnings[?resourceId=mov_d99acbe4734e].status` eq `RESOLVED` → thực tế `None`
- `SC-CLOSE/V2-classify-keeps-summary` — `rec.warnings[?resourceId=mov_f98092164b70].status` eq `RESOLVED` → thực tế `None`

### `CLOSE-UPSERT` — major

- Rule: Đóng lại cùng ngày: upsert 1 record, warning RESOLVED giữ nguyên, warning mới thêm vào, không trùng warningId.
- Nguồn: `implement-plan-backend-poc.md §8`
- `SC-CLOSE/V3-reclose-upsert` — `close2.warnings` len `3` → thực tế `len=2 [{'amount': 120000, 'message': 'Giao dịch 120.000đ chưa được xác nhận.', 'resolvedAt': '2026-09-12T12:58:16+07:00', 'resourceId': 'ev_4a8be6f54e84', 'resourceType': 'EVENT', 'status': 'RESOLVED', 'type': 'DRAFT_EVENT', 'warningId': 'DRAFT_EVENT:ev_4a8be6f54e84'}, {'amount': 100000, 'message': 'Giao dịch 100.000đ chưa được xác nhận.', 'resolvedAt': None, 'resourceId': 'ev_a9bc05fa606b', 'resourceType': 'EVENT', 'status': 'OPEN', 'type': 'DRAFT_EVENT', 'warningId': 'DRAFT_EVENT:ev_a9bc05fa606b'}]` · 1 cũ đã RESOLVED + 2 mới
- `SC-CLOSE/V3-reclose-upsert` — `close2.warnings[*].warningId` contains `UNMATCHED_MONEY:mov_a596b3c222c1` → thực tế `['DRAFT_EVENT:ev_4a8be6f54e84', 'DRAFT_EVENT:ev_a9bc05fa606b']`

### `CLOSE-WARNING-ID` — major

- Rule: warningId = 'DRAFT_EVENT:{eventId}' | 'UNMATCHED_MONEY:{movementId}'.
- Nguồn: `implement-plan-backend-poc.md §8`
- `SC-CLOSE/V1-generate-and-resolve` — `close1.warnings[*].warningId` contains `UNMATCHED_MONEY:mov_d99acbe4734e` → thực tế `['DRAFT_EVENT:ev_b08f9386d655', 'DRAFT_EVENT:ev_ccb3d8d7f070']`

### `CLOSE-WARNING-SCOPE` — major

- Rule: Chỉ event DRAFT và movement UNMATCHED sinh warning.
- Nguồn: `implement-plan-backend-poc.md §8`
- `SC-CLOSE/V1-generate-and-resolve` — `close1.warnings[?resourceId=mov_d99acbe4734e].resourceType` eq `MONEY_MOVEMENT` → thực tế `None`

### `CLS-REVENUE-INVARIANT` — critical · **HERO**

- Rule: Sau classify, dashboard chỉ đổi đúng unmatchedMoneyCount; revenue/expense/collected/receivable/bankIn/draftCount y nguyên.
- Nguồn: `CLAUDE.md §6 + feature-map/match-classify-money.md`
- `SC-HERO/V2-classify-deposit` — `.` diffOnlyKeys `{'unmatchedMoneyCount': -1}` → thực tế `đổi: {'pastUnmatchedCount': [1, 0]}` · HERO: đúng một key được phép đổi; revenue/expense/collected/receivable/bankIn/draftCount y nguyên
- `SC-HERO/V3-classify-owner-money` — `.` diffOnlyKeys `{'unmatchedMoneyCount': -1}` → thực tế `đổi: {'pastUnmatchedCount': [1, 0]}`

### `DASH-BANKIN` — critical · **HERO**

- Rule: bankIn = Σ amount mọi movement direction=IN, bất kể status.
- Nguồn: `CLAUDE.md §6`
- `SC-CAND/V4-hero-no-candidate` — `dash.bankIn` eq `380000` → thực tế `0` · tiền vào ngân hàng tăng ngay khi capture
- `SC-HERO/V2-classify-deposit` — `dashAfter.bankIn` eq `380000` → thực tế `0`
- `SC-HERO/V3-classify-owner-money` — `dashAfter.bankIn` eq `5000000` → thực tế `0`
- `SC-HERO/V4-bankin-all-status` — `dash0.bankIn` eq `1530000` → thực tế `0` · 900k + 380k + 250k
- `SC-HERO/V4-bankin-all-status` — `dash3.bankIn` eq `1530000` → thực tế `0`

### `DASH-COUNTS` — major

- Rule: draftCount = số event DRAFT; unmatchedMoneyCount = số movement UNMATCHED.
- Nguồn: `implement-plan-backend-poc.md §7`
- `SC-CAND/V4-hero-no-candidate` — `dash.unmatchedMoneyCount` eq `1` → thực tế `0`
- `SC-HERO/V1-match-effects` — `.unmatchedMoneyCount` delta `-1` → thực tế `0 → 0 (delta 0)`
- `SC-HERO/V4-bankin-all-status` — `dash0.unmatchedMoneyCount` eq `3` → thực tế `0`
- `SC-HERO/V4-bankin-all-status` — `dash1.unmatchedMoneyCount` eq `2` → thực tế `0`
- `SC-HERO/V4-bankin-all-status` — `dash2.unmatchedMoneyCount` eq `1` → thực tế `0`

## 6. Hành vi chưa định nghĩa (probe — không tính pass/fail)

### `SC-CAND/P1-name-normalize`

- Câu hỏi: similar() so token BẰNG hay so CHỨA? Có bỏ dấu, bỏ hoa/thường, bỏ tiền tố (chị/anh/o) không?
- Ảnh hưởng: Nếu không bỏ dấu thì mọi so tên đều trượt, điểm kẹt ở 0.7 và thứ tự candidate sai khi có nhiều đơn cùng mệnh giá.
- Quan sát `mov.candidates[*].eventId` = `["ev_6cd8bf274047", "ev_ee07a8af2225", "ev_272f14cc5e16"]`
- Quan sát `mov.candidates[*].score` = `[0.9, 0.9, 0.6]`

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

## 7. Độ trễ

| Endpoint | Gọi AI | n | p50 | p95 | max |
|---|---|---|---|---|---|
| `GET /api/daily-records` | — | 2 | 234ms | 234ms | 234ms |
| `GET /api/daily-records/2026-09-07` | — | 1 | 216ms | 216ms | 216ms |
| `GET /api/daily-records/2026-09-12` | — | 4 | 238ms | 246ms | 246ms |
| `GET /api/dashboard` | — | 24 | 244ms | 272ms | 279ms |
| `GET /api/events` | — | 7 | 231ms | 237ms | 237ms |
| `GET /api/events/ev_86dda7e5dd3b` | — | 1 | 237ms | 237ms | 237ms |
| `GET /api/events/ev_cecd507ad56d` | — | 1 | 299ms | 299ms | 299ms |
| `GET /api/money-movements` | — | 2 | 238ms | 257ms | 257ms |
| `GET /api/money-movements/mov_038d9084727c` | — | 1 | 256ms | 256ms | 256ms |
| `GET /api/money-movements/mov_126732042f34` | — | 1 | 242ms | 242ms | 242ms |
| `GET /api/money-movements/mov_338e1b825119` | — | 2 | 231ms | 235ms | 235ms |
| `GET /api/money-movements/mov_35f8b7b8648a` | — | 1 | 227ms | 227ms | 227ms |
| `GET /api/money-movements/mov_40103478d08c` | — | 2 | 256ms | 267ms | 267ms |
| `GET /api/money-movements/mov_526098ff3124` | — | 1 | 231ms | 231ms | 231ms |
| `GET /api/money-movements/mov_7a59cdcd2cac` | — | 1 | 277ms | 277ms | 277ms |
| `GET /api/money-movements/mov_7ee5a77bf887` | — | 2 | 249ms | 250ms | 250ms |
| `GET /api/money-movements/mov_8c60aa03e8f8` | — | 2 | 221ms | 228ms | 228ms |
| `GET /api/money-movements/mov_cbf42f6611fb` | — | 3 | 251ms | 252ms | 252ms |
| `GET /api/money-movements/mov_d0b2e8475706` | — | 2 | 356ms | 468ms | 468ms |
| `GET /api/money-movements/mov_d99acbe4734e` | — | 1 | 240ms | 240ms | 240ms |
| `GET /api/money-movements/mov_f482c41c413f` | — | 1 | 265ms | 265ms | 265ms |
| `GET /api/money-movements/mov_khong_ton_tai` | — | 1 | 245ms | 245ms | 245ms |
| `POST /api/captures` | có | 73 | 1909ms | 2944ms | 7030ms |
| `POST /api/close-day` | — | 9 | 293ms | 309ms | 309ms |
| `POST /api/events/ev_0458d614aca0/confirm` | — | 1 | 269ms | 269ms | 269ms |
| `POST /api/events/ev_0577951f3d2e/confirm` | — | 1 | 254ms | 254ms | 254ms |
| `POST /api/events/ev_073817aca898/confirm` | — | 1 | 284ms | 284ms | 284ms |
| `POST /api/events/ev_0d4816e61a66/confirm` | — | 1 | 277ms | 277ms | 277ms |
| `POST /api/events/ev_1350541c942d/confirm` | — | 1 | 244ms | 244ms | 244ms |
| `POST /api/events/ev_272f14cc5e16/confirm` | — | 1 | 266ms | 266ms | 266ms |
| `POST /api/events/ev_27f0e6655b27/confirm` | — | 1 | 256ms | 256ms | 256ms |
| `POST /api/events/ev_2d3ef9c01b7c/confirm` | — | 1 | 249ms | 249ms | 249ms |
| `POST /api/events/ev_3c353eece133/confirm` | — | 1 | 248ms | 248ms | 248ms |
| `POST /api/events/ev_3ef4a9ea8839/reject` | — | 1 | 259ms | 259ms | 259ms |
| `POST /api/events/ev_41bac9359082/confirm` | — | 1 | 275ms | 275ms | 275ms |
| `POST /api/events/ev_445b6579a8b1/confirm` | — | 1 | 249ms | 249ms | 249ms |
| `POST /api/events/ev_4a8be6f54e84/confirm` | — | 1 | 283ms | 283ms | 283ms |
| `POST /api/events/ev_4c225de7546a/confirm` | — | 1 | 258ms | 258ms | 258ms |
| `POST /api/events/ev_4fc0e05b06d4/confirm` | — | 1 | 264ms | 264ms | 264ms |
| `POST /api/events/ev_5311d7f16933/confirm` | — | 1 | 253ms | 253ms | 253ms |
| `POST /api/events/ev_532c6313aebb/confirm` | — | 1 | 289ms | 289ms | 289ms |
| `POST /api/events/ev_5a9d6e7bb1b3/confirm` | — | 1 | 301ms | 301ms | 301ms |
| `POST /api/events/ev_5e77dd4f3ff7/confirm` | — | 1 | 255ms | 255ms | 255ms |
| `POST /api/events/ev_5f1dc8b0d6ac/reject` | — | 1 | 258ms | 258ms | 258ms |
| `POST /api/events/ev_664a7ce55476/reject` | — | 1 | 279ms | 279ms | 279ms |
| `POST /api/events/ev_6728643a8c0a/confirm` | — | 1 | 261ms | 261ms | 261ms |
| `POST /api/events/ev_6815b84f235a/confirm` | — | 1 | 261ms | 261ms | 261ms |
| `POST /api/events/ev_6cd8bf274047/confirm` | — | 1 | 244ms | 244ms | 244ms |
| `POST /api/events/ev_70a9488e30b8/confirm` | — | 1 | 257ms | 257ms | 257ms |
| `POST /api/events/ev_823f8a781aa6/confirm` | — | 1 | 257ms | 257ms | 257ms |
| `POST /api/events/ev_86dda7e5dd3b/confirm` | — | 1 | 238ms | 238ms | 238ms |
| `POST /api/events/ev_87ba96764989/confirm` | — | 1 | 239ms | 239ms | 239ms |
| `POST /api/events/ev_88108ee3e4cf/confirm` | — | 1 | 271ms | 271ms | 271ms |
| `POST /api/events/ev_90f9b2e49cdc/confirm` | — | 1 | 255ms | 255ms | 255ms |
| `POST /api/events/ev_99a970b022b9/confirm` | — | 1 | 269ms | 269ms | 269ms |
| `POST /api/events/ev_99c10e328d1d/confirm` | — | 1 | 262ms | 262ms | 262ms |
| `POST /api/events/ev_9c40ae17157e/confirm` | — | 1 | 261ms | 261ms | 261ms |
| `POST /api/events/ev_9e38ab0c3fa3/confirm` | — | 1 | 237ms | 237ms | 237ms |
| `POST /api/events/ev_9f07626fd0a9/confirm` | — | 1 | 250ms | 250ms | 250ms |
| `POST /api/events/ev_b08f9386d655/confirm` | — | 1 | 286ms | 286ms | 286ms |
| `POST /api/events/ev_b721d1166667/confirm` | — | 1 | 289ms | 289ms | 289ms |
| `POST /api/events/ev_b7dfef3f1f71/confirm` | — | 1 | 290ms | 290ms | 290ms |
| `POST /api/events/ev_bea5d4099a97/confirm` | — | 1 | 249ms | 249ms | 249ms |
| `POST /api/events/ev_c633cd2b1c7a/confirm` | — | 1 | 276ms | 276ms | 276ms |
| `POST /api/events/ev_cb14ba9afdd2/confirm` | — | 1 | 259ms | 259ms | 259ms |
| `POST /api/events/ev_ccb3d8d7f070/reject` | — | 1 | 307ms | 307ms | 307ms |
| `POST /api/events/ev_cdeb419d9446/confirm` | — | 1 | 270ms | 270ms | 270ms |
| `POST /api/events/ev_ce35deed855d/confirm` | — | 1 | 299ms | 299ms | 299ms |
| `POST /api/events/ev_daf456daa77e/confirm` | — | 1 | 256ms | 256ms | 256ms |
| `POST /api/events/ev_ee07a8af2225/confirm` | — | 1 | 262ms | 262ms | 262ms |
| `POST /api/events/ev_f4b5b4260c73/confirm` | — | 1 | 253ms | 253ms | 253ms |
| `POST /api/events/ev_f838265cdebb/confirm` | — | 1 | 287ms | 287ms | 287ms |
| `POST /api/money-movements/mov_038d9084727c/classify` | — | 2 | 242ms | 256ms | 256ms |
| `POST /api/money-movements/mov_038d9084727c/match` | — | 1 | 236ms | 236ms | 236ms |
| `POST /api/money-movements/mov_126732042f34/match` | — | 1 | 276ms | 276ms | 276ms |
| `POST /api/money-movements/mov_2bca884fb293/match` | — | 1 | 290ms | 290ms | 290ms |
| `POST /api/money-movements/mov_35f8b7b8648a/match` | — | 1 | 304ms | 304ms | 304ms |
| `POST /api/money-movements/mov_526098ff3124/classify` | — | 1 | 255ms | 255ms | 255ms |
| `POST /api/money-movements/mov_5f8c74ff29d4/classify` | — | 1 | 241ms | 241ms | 241ms |
| `POST /api/money-movements/mov_7a59cdcd2cac/classify` | — | 3 | 211ms | 214ms | 214ms |
| `POST /api/money-movements/mov_7a59cdcd2cac/match` | — | 2 | 258ms | 269ms | 269ms |
| `POST /api/money-movements/mov_8727da52f436/match` | — | 1 | 287ms | 287ms | 287ms |
| `POST /api/money-movements/mov_8c60aa03e8f8/classify` | — | 1 | 236ms | 236ms | 236ms |
| `POST /api/money-movements/mov_8c60aa03e8f8/match` | — | 2 | 263ms | 295ms | 295ms |
| `POST /api/money-movements/mov_93be022e8687/match` | — | 1 | 279ms | 279ms | 279ms |
| `POST /api/money-movements/mov_a26dbd842f22/classify` | — | 1 | 250ms | 250ms | 250ms |
| `POST /api/money-movements/mov_be261fbb7a58/classify` | — | 1 | 246ms | 246ms | 246ms |
| `POST /api/money-movements/mov_d99acbe4734e/match` | — | 1 | 328ms | 328ms | 328ms |
| `POST /api/money-movements/mov_f98092164b70/classify` | — | 1 | 243ms | 243ms | 243ms |
| `POST /api/register` | — | 20 | 429ms | 521ms | 521ms |
| `PUT /api/events/ev_0458d614aca0` | — | 1 | 253ms | 253ms | 253ms |
| `PUT /api/events/ev_0577951f3d2e` | — | 1 | 257ms | 257ms | 257ms |
| `PUT /api/events/ev_073817aca898` | — | 1 | 245ms | 245ms | 245ms |
| `PUT /api/events/ev_0d4816e61a66` | — | 1 | 273ms | 273ms | 273ms |
| `PUT /api/events/ev_1350541c942d` | — | 1 | 242ms | 242ms | 242ms |
| `PUT /api/events/ev_272f14cc5e16` | — | 1 | 244ms | 244ms | 244ms |
| `PUT /api/events/ev_27f0e6655b27` | — | 1 | 250ms | 250ms | 250ms |
| `PUT /api/events/ev_2d3ef9c01b7c` | — | 1 | 255ms | 255ms | 255ms |
| `PUT /api/events/ev_3c353eece133` | — | 1 | 240ms | 240ms | 240ms |
| `PUT /api/events/ev_3ef4a9ea8839` | — | 1 | 261ms | 261ms | 261ms |
| `PUT /api/events/ev_41bac9359082` | — | 1 | 251ms | 251ms | 251ms |
| `PUT /api/events/ev_445b6579a8b1` | — | 1 | 245ms | 245ms | 245ms |
| `PUT /api/events/ev_4a8be6f54e84` | — | 1 | 257ms | 257ms | 257ms |
| `PUT /api/events/ev_4c225de7546a` | — | 1 | 253ms | 253ms | 253ms |
| `PUT /api/events/ev_4fc0e05b06d4` | — | 1 | 276ms | 276ms | 276ms |
| `PUT /api/events/ev_5311d7f16933` | — | 1 | 253ms | 253ms | 253ms |
| `PUT /api/events/ev_532c6313aebb` | — | 1 | 284ms | 284ms | 284ms |
| `PUT /api/events/ev_5a9d6e7bb1b3` | — | 1 | 258ms | 258ms | 258ms |
| `PUT /api/events/ev_5e77dd4f3ff7` | — | 1 | 248ms | 248ms | 248ms |
| `PUT /api/events/ev_5f1dc8b0d6ac` | — | 1 | 257ms | 257ms | 257ms |
| `PUT /api/events/ev_664a7ce55476` | — | 1 | 260ms | 260ms | 260ms |
| `PUT /api/events/ev_6728643a8c0a` | — | 1 | 272ms | 272ms | 272ms |
| `PUT /api/events/ev_67510e85f285` | — | 1 | 315ms | 315ms | 315ms |
| `PUT /api/events/ev_6815b84f235a` | — | 1 | 248ms | 248ms | 248ms |
| `PUT /api/events/ev_6cd8bf274047` | — | 1 | 247ms | 247ms | 247ms |
| `PUT /api/events/ev_70a9488e30b8` | — | 1 | 264ms | 264ms | 264ms |
| `PUT /api/events/ev_823f8a781aa6` | — | 1 | 243ms | 243ms | 243ms |
| `PUT /api/events/ev_86dda7e5dd3b` | — | 1 | 239ms | 239ms | 239ms |
| `PUT /api/events/ev_87ba96764989` | — | 1 | 259ms | 259ms | 259ms |
| `PUT /api/events/ev_88108ee3e4cf` | — | 1 | 255ms | 255ms | 255ms |
| `PUT /api/events/ev_90f9b2e49cdc` | — | 1 | 258ms | 258ms | 258ms |
| `PUT /api/events/ev_99a970b022b9` | — | 1 | 259ms | 259ms | 259ms |
| `PUT /api/events/ev_99c10e328d1d` | — | 1 | 245ms | 245ms | 245ms |
| `PUT /api/events/ev_9c40ae17157e` | — | 1 | 248ms | 248ms | 248ms |
| `PUT /api/events/ev_9e38ab0c3fa3` | — | 1 | 263ms | 263ms | 263ms |
| `PUT /api/events/ev_9f07626fd0a9` | — | 1 | 242ms | 242ms | 242ms |
| `PUT /api/events/ev_9f1be8aa4dbc` | — | 1 | 263ms | 263ms | 263ms |
| `PUT /api/events/ev_a9bc05fa606b` | — | 1 | 274ms | 274ms | 274ms |
| `PUT /api/events/ev_b08f9386d655` | — | 1 | 240ms | 240ms | 240ms |
| `PUT /api/events/ev_b721d1166667` | — | 1 | 273ms | 273ms | 273ms |
| `PUT /api/events/ev_b7dfef3f1f71` | — | 1 | 258ms | 258ms | 258ms |
| `PUT /api/events/ev_bea5d4099a97` | — | 1 | 268ms | 268ms | 268ms |
| `PUT /api/events/ev_c633cd2b1c7a` | — | 1 | 281ms | 281ms | 281ms |
| `PUT /api/events/ev_cb14ba9afdd2` | — | 1 | 263ms | 263ms | 263ms |
| `PUT /api/events/ev_ccb3d8d7f070` | — | 1 | 261ms | 261ms | 261ms |
| `PUT /api/events/ev_cdeb419d9446` | — | 1 | 260ms | 260ms | 260ms |
| `PUT /api/events/ev_ce35deed855d` | — | 1 | 267ms | 267ms | 267ms |
| `PUT /api/events/ev_cecd507ad56d` | — | 1 | 249ms | 249ms | 249ms |
| `PUT /api/events/ev_daf456daa77e` | — | 1 | 262ms | 262ms | 262ms |
| `PUT /api/events/ev_ee07a8af2225` | — | 1 | 256ms | 256ms | 256ms |
| `PUT /api/events/ev_f4b5b4260c73` | — | 1 | 267ms | 267ms | 267ms |
| `PUT /api/events/ev_f838265cdebb` | — | 1 | 265ms | 265ms | 265ms |
