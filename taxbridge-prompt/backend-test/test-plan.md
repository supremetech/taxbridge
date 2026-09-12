# Test plan — độ chính xác xử lý BACK-END

Bộ `../test-data/` đo **AI trích xuất đúng không**. Bộ này đo **back-end xử lý đúng không**:
thuật toán chấm candidate, hệ quả của ghép/phân loại tiền, 7 công thức dashboard, vòng đời
warning khi đóng ngày. Hai bộ không thay thế nhau.

## Vì sao cần bộ riêng

Sáng 12/09 chạy bộ eval AI hai lần: account `tuan` cho `warningCount = 2`, account `binh`
cho `3`. Hóa ra do người khác dùng chung account — nhưng **bộ eval AI không có cách nào
phân biệt "backend sai" với "dữ liệu nhiễu"**. Bộ này lấp đúng chỗ đó bằng hai cơ chế:

- **Mỗi variation một business mới** (`POST /api/register`, không gọi AI) ⇒ kỳ vọng là giá
  trị tuyệt đối, không ai giẫm vào ai.
- **`FAIL` ≠ `BLOCKED`**: giá trị do AI sinh chỉ được dùng trong `precheck`. AI đọc lệch ảnh
  ⇒ variation `BLOCKED`, **không tính vào điểm back-end**.

## Cách dựng dữ liệu tất định

| Vấn đề | Cách giải |
|---|---|
| Không có endpoint seed | `POST /api/captures` (TEXT, câu cực dễ) → `PUT /api/events/{id}` ép đúng 7 field cho phép → `confirm`/`reject`/để `DRAFT`. Macro `seedEvent` trong scenario JSON |
| Movement không có `PUT` (số tiền do AI đọc ảnh) | Capture ảnh **trước**, `GET` movement, lưu số tiền thật vào `${AMT}`, **rồi mới** seed event theo `${AMT}`, `${AMT-1}`. Không bao giờ hard-code số trên ảnh vào `expect` |
| Trần 3 candidate | Không quá 3 event eligible cùng mệnh giá trong một world, nếu không không đọc được điểm của cái thứ 4 |
| Float | So `score` với dung sai `1e-6` (0.6+0.3+0.1 ra `0.9999999999999999`) |

## Danh mục scenario

| Scenario | Ý đồ test | UC §9 | Variation |
|---|---|---|---|
| `SC-CAND` | Thuật toán candidate là trái tim UC4. Lệch trọng số ⇒ gợi ý sai đơn; lọc pool hỏng ⇒ gợi ý ghép vào đơn đã thu tiền (đếm tiền hai lần); ngưỡng sai ⇒ UC5 hiện candidate rác | UC4, UC5 | 6 |
| `SC-HERO` | Tiền vào ngân hàng tăng, doanh thu **không đổi**. Classify chạm vào `revenue` là banner trên Home nói dối | UC4, UC5 | 7 |
| `SC-CLOSE` | UC7 — hệ thống tự dọn việc tồn: warning sinh đúng, xử lý xong thì `RESOLVED` + `summary` tính lại | UC7 | 4 |
| `SC-DASH` | 7 số trên Home. Sai một dòng là khai thuế sai | UC1, UC2, UC6 | 3 |

### `SC-CAND` — candidate

Công thức (plan BE §6): `score = 0.6·(trùng tiền) + 0.3·(similar tên/memo) + 0.1·(cùng ngày)`,
pool `SALE + CONFIRMED + UNPAID`, giữ `>= 0.3`, tối đa 3, giảm dần, **không bao giờ tự ghép**.

| Variation | Dữ liệu | Kỳ vọng |
|---|---|---|
| `V1-weights` | 3 đơn: (trùng tiền+tên+ngày) · (trùng tiền+tên, khác ngày) · (trùng tiền, khác tên) | `1.0 · 0.9 · 0.7`, sắp giảm dần |
| `V2-threshold` | lệch **1 đồng**: (+tên+ngày)=0.4 · (+tên, khác ngày)=0.3 · (khác tên+ngày)=0.1 | giữ 2 cái đầu; cái 0.1 **bị loại**. Lọt vào ⇒ code dùng `score>0` ⇒ hero UC5 hỏng |
| `V3-pool-filter` | **7 mồi nhử** cùng tiền + cùng tên + cùng ngày (⇒ 1.0 nếu filter hỏng): PAID · DRAFT · REJECTED · PURCHASE · DEPOSIT · OWNER_MONEY · UNKNOWN, cộng 1 đối chứng dương | đúng **1** candidate = đối chứng dương |
| `V4-hero-no-candidate` | đơn 450k + ảnh CK 380k | `candidates: []`, `bankIn` tăng, `revenue` không đổi |
| `V5-ambiguous` | 2 đơn cùng 600k, memo vô nghĩa | đủ **2** candidate, không tự ghép, thứ tự **ổn định** giữa 2 lần đọc |
| `P1-name-normalize` | cùng tiền + cùng ngày, chỉ đổi tên: `Lân` · `chị Lan` · `Lanh` | PROBE: dò `similar()` bỏ dấu / bỏ tiền tố / so bằng hay so chứa |

### `SC-HERO` — ghép và phân loại

| Variation | Kỳ vọng cốt lõi |
|---|---|
| `V1-match-effects` | movement `MATCHED` + `candidates: []`; event `PAID` (vẫn `CONFIRMED`); `collected +AMT`, `receivable −AMT`, `revenue` và `bankIn` **không đổi**, `unmatchedMoneyCount −1`, không tạo event mới |
| `V2-classify-deposit` | **`diffOnlyKeys(dashboard) == {unmatchedMoneyCount: −1}`** — đúng một key được phép đổi. Assertion mạnh nhất của cả bộ |
| `V3-classify-owner-money` | 5 triệu vào `bankIn`, **không** vào `revenue` |
| `V4-bankin-all-status` | `bankIn` = tổng cả 3 khoản ở cả 4 mốc (UNMATCHED / MATCHED / CLASSIFIED) |
| `V5-state-guards` | 4 lệnh sai trạng thái → `409 INVALID_STATE`, và dashboard **không đổi key nào** |
| `V6-invalid-input` | enum sai / thiếu field → 400; id không có → 404; movement giữ nguyên `UNMATCHED` |
| `P2-match-target` | PROBE: `match` vào event DRAFT / PURCHASE / đã PAID. **Mỗi target một movement riêng** — nếu dùng chung thì lệnh thứ hai nhận 409 vì movement đã MATCHED chứ không phải vì backend chặn target |

### `SC-CLOSE` — đóng ngày

| Variation | Kỳ vọng cốt lõi |
|---|---|
| `V1-generate-and-resolve` | 2 draft + 1 tiền chưa ghép ⇒ 3 warning, id đúng `TYPE:resourceId`; confirm → `RESOLVED` + `summary.expense` tăng; reject → `RESOLVED` nhưng doanh thu không đổi; match → `RESOLVED` + `collected` tăng; `closedAt` giữ nguyên suốt |
| `V2-classify-keeps-summary` | hero lặp lại ở tầng sổ ngày: warning sạch nhưng 4 số không đổi |
| `V3-reclose-upsert` | đóng lại: warning cũ vẫn `RESOLVED`, warning mới `OPEN`, `warningCount` chỉ đếm OPEN, vẫn đúng 1 record |
| `V4-history-and-errors` | 3 ngày sort giảm dần, mỗi ngày chỉ gồm giao dịch của ngày đó; ngày chưa đóng → 404; `date` sai → 400 |

### `SC-DASH` — dashboard

`V1-formula` dựng 11 event phủ mọi nhánh lọc:

| Nhóm | Event |
|---|---|
| SALE | CONFIRMED/UNPAID 450k · CONFIRMED/PAID 720k · CONFIRMED/**UNKNOWN** 250k · **DRAFT** 999k · **REJECTED** 888k |
| PURCHASE | CONFIRMED 220k · **DRAFT** 180k · **REJECTED** 111k |
| Khác | **DEPOSIT** 380k · **OWNER_MONEY** 500k · **UNKNOWN** 123k |

⇒ `revenue 1.420.000` · `expense 220.000` · `collected 720.000` (đơn `paymentStatus=UNKNOWN`
vào doanh thu **nhưng không** vào tiền đã thu) · `receivable 700.000` · `draftCount 2`.

`V2-date-filter` dò biên `T00:00:00` / `T23:59:59` và mặc định "hôm nay".
`V3-empty-business` business trắng: 7 số bằng 0, không null, không 404.

## Chỉ số trong report

| Chỉ số | Vì sao cần |
|---|---|
| `backendAccuracy` | pass/(pass+fail), **đã loại BLOCKED** — không lẫn lỗi AI |
| `demoReadiness` theo 9 UC | nhìn một dòng biết có dám lên sân khấu không |
| `wrongAutoMatchCount` · `revenueInvarianceViolations` · `illegalTransitionSucceeded` | ba con số phải bằng 0, mỗi cái khác 0 là hỏng một thông điệp sản phẩm |
| `weightRegression` | **giải ngược** `(w_amount, w_name, w_day)` từ score quan sát. Ra `(0.6, 0.3, 0.1)` = khớp spec; ra `(0.6, 0.0, 0.1)` = biết ngay `similar()` chết |
| `moneyExactRate` | tiền sai là sai nặng nhất với hộ kinh doanh |
| `blockedRate` | mức nhiễu AI — cầu nối sang bộ `test-data/` |
| `latency` tách AI-path | đo back-end thật, không đo OpenAI |

## Chưa làm (sau demo)

`AUTH` (token, 5 route public, cách ly business) · `VAL` (whitelist 7 field `PUT`, 413/415,
biên 10 MB) · `CAP`/`EVID` (định tuyến type, AI lỗi = 200+FAILED, `occurredAt = now()`,
`HEAD evidenceUrl`) · `EVT` (ma trận 3 trạng thái × 3 hành động) · `ZALO` (secret, chưa link,
đã link, remux `.aac` → `.m4a`) · `DTO` (13 bất biến chạy trên mọi response) · `compare.py`.
`direction=OUT` chưa test được vì không có fixture ảnh "chuyển đi".
