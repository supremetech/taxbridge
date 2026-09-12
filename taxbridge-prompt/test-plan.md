# TaxBridge — Test plan tổng (AI extraction + back-end)

Hai bộ test, hai câu hỏi khác nhau, **không thay thế nhau**:

| Bộ | Câu hỏi | Thư mục | Chạy |
|---|---|---|---|
| **AI extraction** | AI đọc đúng text / giọng nói / ảnh không? | `test-data/` | `run_cases.py` → `score.py` |
| **Back-end** | Hệ thống xử lý đúng không? (candidate, tiền vào, dashboard, sổ ngày, Phase 2) | `backend-test/` | `run.py` → `score.py` |

Ranh giới giữa hai bộ là **luật bất di bất dịch**: trong `backend-test`, mọi giá trị do AI
sinh ra (số tiền đọc từ ảnh, memo, counterparty, ngày trên chứng từ) chỉ được dùng trong
`precheck`. AI đọc lệch ⇒ variation `BLOCKED`, **không tính vào điểm back-end**. Nếu không có
ranh giới này thì một lỗi AI sẽ bị báo cáo nhầm thành lỗi logic, và ngược lại.

## 1. Vì sao cần hai bộ

Sáng 12/09 bộ AI chạy hai vòng: `tuan` cho `warningCount = 2`, `binh` cho `3`. Nguyên nhân
là người khác thao tác cùng lúc trên account dùng chung — nhưng **bộ AI không có cách nào
phân biệt "backend sai" với "dữ liệu nhiễu"**, và nó cũng không hề chạm tới thuật toán chấm
candidate hay vòng đời warning. Hai khoảng trống đó là lý do `backend-test/` ra đời.

Từ đó cả hai bộ đều **tự đăng ký account mới cho mỗi vòng chạy** (`backend-test`: mỗi
variation một account; `test-data`: mỗi vòng một account), nên kỳ vọng là giá trị tuyệt đối
và không ai giẫm lên ai.

## 2. Bộ AI extraction — `test-data/`

21 case, ngành đặc sản Tây Bắc, ngày mô phỏng 11/09/2026. Mỗi case có ground truth và chấm
tự động; chi tiết thiết kế ở `test-data/README.md`.

| Loại | Số case | Bẫy chính |
|---|---|---|
| TEXT | 6 | không nói hình thức thanh toán → `UNKNOWN`; chủ hộ bỏ tiền vào quỹ → `OWNER_MONEY`; "1 triệu 250" = 1.250.000 |
| AUDIO | 4 | giọng miền Trung + ồn SNR 12dB; nói vấp tự sửa giữa câu; câu không có nghiệp vụ nhưng có số |
| IMAGE_RECEIPT | 3 | hóa đơn in mờ có cả tiền khách đưa và tiền thối; ảnh nhãn sản phẩm không phải chứng từ |
| IMAGE_TRANSFER | 7 | **bẫy tên**: ảnh khách chụp nên tên hiển thị là chủ shop; 600k khớp 2 đơn; lệch 8.000 do phí |
| CLOSE_DAY | 1 | 4 số tổng hợp + warning |

Chấm tự động chỉ trên critical field (`type, amount, paymentMethod, paymentStatus` /
`direction, amount, status, classificationType`); `description`, `counterparty` chấm tay qua
`human_grading.md`. Chỉ số riêng cho hero: tỉ lệ top-1 đúng, độ phủ candidate, số lần tự ghép
sai, tỉ lệ dính bẫy tên.

**Ảnh hưởng của Phase 2 ②** (`occurredAt` = ngày in trên chứng từ): ảnh trong bộ fixture in
ngày 11/09 nên rơi vào sổ 11/09, còn text/voice không nêu ngày thì rơi vào hôm nay ⇒ một
"ngày nghiệp vụ" của bộ case bị tách làm hai ngày thật. `run_cases.py` vì thế đóng **mọi**
ngày có bản ghi và lấy 4 số của case D1 từ `GET /api/reports?from&to` thay vì từ một
`daily_record` duy nhất. Bộ case **không đổi** — vẫn so được với baseline cũ.

## 3. Bộ back-end — `backend-test/`

Scenario = một ý đồ test; mỗi scenario có nhiều variation dữ liệu kèm kết quả có sẵn. Ý đồ
từng scenario và bảng variation đầy đủ: `backend-test/test-plan.md`.

| Scenario | Ý đồ | UC |
|---|---|---|
| `SC-CAND` | Thuật toán candidate: trọng số `0.6/0.3/0.1`, ngưỡng `≥0.3`, lọc pool `SALE+CONFIRMED+UNPAID`, trần 3, **không bao giờ tự ghép** | UC4, UC5 |
| `SC-HERO` | Ghép/phân loại tiền: match kéo theo `PAID` + `collected`; classify **không đụng doanh thu** | UC4, UC5 |
| `SC-CLOSE` | Sổ ngày: sinh warning, `sync_record` sau mỗi thao tác, đóng lại không nhân đôi, lịch sử | UC7 |
| `SC-DASH` | 7 số trên Home + lọc theo ngày + business trắng | UC1, UC2, UC6 |
| `SC-DATE` | **Phase 2 ②** — ảnh quyết định ngày; text không nêu ngày vẫn là hôm nay | UC10 |
| `SC-REPORT` | **Phase 2 ③④** — tổng báo cáo = tổng dòng ngày; tồn đọng gom mọi ngày | UC12, UC13 |
| `SC-BATCH` | **Phase 2 ①** — ảnh lịch sử CK → N movement, gửi lại không tạo trùng, ảnh sai loại bị từ chối, dòng `OUT` không vào `bankIn` | UC14 |

Kỹ thuật dựng dữ liệu tất định:

- `seedEvent` — capture TEXT một câu cực dễ → `PUT` ép đúng 7 field cho phép → confirm/reject/
  để DRAFT. State event chính xác dù AI trích xuất lệch.
- Movement không có `PUT` ⇒ **neo theo giá trị quan sát**: chụp ảnh trước, lưu số tiền thật
  vào `${AMT}` và ngày chứng từ vào `${MDATE}`, rồi mới seed event theo hai biến đó. Sau
  Phase 2 ② thì `${MDATE}` là bắt buộc: "cùng ngày" nghĩa là cùng ngày **trên chứng từ**.
- `--dry-run` kiểm tra rule id, bước tồn tại, và **biến phải được định nghĩa trước khi dùng** —
  bắt được đúng loại lỗi phát sinh khi chuyển sang Phase 2.

## 4. Chỉ số đánh giá

Bộ AI: pass/fail từng case, accuracy từng field, confusion matrix `type`, 4 chỉ số hero.

Bộ back-end (`run-report.json`):

| Chỉ số | Ý nghĩa |
|---|---|
| `backendAccuracy` | pass/(pass+fail), **đã loại BLOCKED** — không lẫn lỗi AI |
| `demoReadiness` theo UC | `READY / AT_RISK / BROKEN` cho từng use case §9 + Phase 2 |
| `wrongAutoMatchCount` · `revenueInvarianceViolations` · `illegalTransitionSucceeded` | ba con số **phải = 0** |
| `weightRegression` | giải ngược `(w_amount, w_name, w_day)` từ score quan sát — chẩn đoán nhanh hơn hàng chục dòng pass/fail |
| `moneyExactRate` · `blockedRate` · `ruleCoverage` | tiền, mức nhiễu AI, độ phủ rule |
| `latency` tách AI-path | đo back-end thật, không đo OpenAI |

## 5. Chạy cả hai bộ

```bash
cd taxbridge-prompt
python3 backend-test/run.py --out runs/<tên-vòng> && python3 backend-test/score.py runs/<tên-vòng>
python3 test-data/run_cases.py --out runs/<tên-vòng> && python3 test-data/score.py runs/<tên-vòng>/actual.json
```

Đặt tên vòng theo **thứ đã thay đổi** (`2026-09-12-phase2`), không đặt theo ngày suông — mục
đích của `runs/` là so trước/sau mỗi lần sửa prompt hoặc logic.

Mỗi vòng đầy đủ tốn khoảng 6 phút back-end + 2 phút AI, để lại ~25 account `tbtest_*` /
`eval_*` trên Firestore (không có API xóa; danh sách ở `accounts.json`).

## 6. Quy tắc khi có FAIL

1. Gom theo **nguyên nhân chung**, sửa một chỗ — không vá lẻ từng case (tránh overfit).
2. **Không sửa expected để lách.** Lệch giữa test và spec thì sửa spec hoặc sửa code.
3. Spec chưa định nghĩa → chuyển variation sang `mode: "probe"`, ghi nhận hành vi thật và đưa
   vào mục "hành vi chưa định nghĩa" của report để team chốt.
4. `BLOCKED` cao nghĩa là AI đọc lệch, **không** phải back-end sai — đọc đúng cột này để khỏi
   đổ oan.

## 7. Chưa phủ

`AUTH` (token, 5 route public, cách ly business — đã probe tay 12/09, đúng hết) · `VAL`
(whitelist 7 field `PUT`, 413/415, biên 10 MB) · `CAP`/`EVID` (routing type, `HEAD evidenceUrl`,
`source`/`captureType` không null) · `EVT` (ma trận 3 trạng thái × 3 hành động) · `ZALO`
(secret, chưa link/đã link, replay Phase 2 ③b, remux `.aac` → `.m4a`, bot reply Phase 2 ⑤ —
cần `ZALO_WEBHOOK_SECRET`) · `DTO` (13 bất biến trên mọi response) · `compare.py` so hai vòng.
