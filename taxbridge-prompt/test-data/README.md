# TaxBridge — Bộ eval AI extraction (1 ngày, 21 case)

Bộ dữ liệu thử nghiệm để **đo và tune độ chính xác** của AI extraction trong
TaxBridge PoC. Không phải seed data để demo — mỗi case có ground truth đi kèm và
chấm được tự động.

Ngành hàng: **đặc sản Tây Bắc** (bán lẻ, ít SKU) — giá sản phẩm lấy theo mặt bằng
thị trường thật. Ngày mô phỏng: **11/09/2026**.

> Toàn bộ ảnh và audio là **fixture tổng hợp**. Thương hiệu ngân hàng, tên người,
> số tài khoản, mã giao dịch, mã số thuế đều hư cấu và có dấu synthetic trên ảnh.
> Không dùng ngoài mục đích test.

---

## Chạy một lần eval

Mỗi lần chạy eval = **một thư mục con mới trong `runs/`**. Bạn chỉ tạo đúng một
file trong đó là `actual.json`; ba file còn lại do `score.py` sinh ra.

### 1. Đặt tên thư mục theo thứ đã thay đổi

Mục đích chính của `runs/` là so sánh trước/sau mỗi lần sửa prompt, nên tên nên
nói rõ vòng đó sửa gì — đặt theo ngày không thôi thì vài vòng sau không nhớ nổi:

```text
runs/2026-09-12-baseline/
runs/2026-09-12-prompt-v2-fix-sotien/
runs/2026-09-13-prompt-v3-fix-counterparty/
```

### 2. Chạy 21 case qua backend, gom vào `actual.json`

Một object, key là caseId, value là DTO backend trả về:

```json
{
  "T1": { "type": "SALE", "amount": 900000, "description": "...",
          "counterparty": "...", "paymentMethod": "BANK", "paymentStatus": "UNPAID" },
  "M1": { "direction": "IN", "amount": 900000, "memo": "...", "counterparty": "...",
          "status": "UNMATCHED", "classificationType": null,
          "candidates": [ { "eventId": "T1", "score": 0.9 } ] },
  "A4": null,
  "D1": { "summary": { "revenue": 0, "expense": 0, "collected": 0, "receivable": 0 },
          "warningCount": 0 }
}
```

Lưu ý khi gom:

- Case kỳ vọng không tạo event (`A4`, `R3`): để `null`, hoặc để nguyên DTO mà
  backend trả nếu nó vẫn tạo — scorer cần thấy để biết AI có bịa hay không.
- Case `IMAGE_TRANSFER`: phải kèm `candidates` đúng thứ tự API trả, vì scorer
  chấm cả top-1 và độ phủ candidate.
- `D1` chỉ chạy **sau khi** đã thực hiện `expectedUserAction` của 20 case kia
  (confirm / match / classify), nếu không 4 số tổng hợp sẽ không khớp.
- Mẫu đầy đủ: `runs/example-flawed-run/actual.json`.

### 3. Chấm điểm

```bash
python3 score.py runs/2026-09-12-baseline/actual.json
```

Sinh ra 3 file ngay cạnh `actual.json`:

| File | Nội dung |
|---|---|
| `report.md` | pass/fail từng case, accuracy từng field, confusion matrix, chỉ số hero use case |
| `run-report.json` | dữ liệu thô, dùng để so sánh giữa các vòng tune |
| `human_grading.md` | phiếu chấm tay cho soft field (`description`, `counterparty`) |

### 4. Chấm tay soft field (tuỳ chọn)

`score.py` không tự chấm `description` và `counterparty` vì "Bán 3 hộp tỏi đen
cô đơn" và "3 hộp tỏi đen" đều đúng. Mở `human_grading.md`, tick Đ/S khoảng 36 dòng.

Hai điều cần biết trước khi bỏ công tick:

- **`score.py` hiện không đọc ngược lại file này** — tick xong không ra con số nào
  trong report và không so sánh được giữa các vòng.
- Lỗi counterparty nguy hiểm nhất (AI lấy tên chủ shop làm counterparty trên ảnh
  khách chụp) **đã được chấm tự động** trong `report.md`. Phần còn lại trên phiếu
  tay nhẹ hơn nhiều, bỏ qua ở vài vòng đầu cũng không mất gì quan trọng.

### 5. So sánh giữa các vòng

```bash
python3 -c "
import json,sys
for f in sys.argv[1:]:
    r=json.load(open(f))
    print(f\"{f.split('/')[-2]:42s} pass {r['pass']:2d}/{r['total']}  \"
          f\"bẫy tên {r['counterpartyTrap']['hit']}/{r['counterpartyTrap']['total']}  \"
          f\"tự ghép sai {r['matching']['wrong_automatch']}\")
" runs/*/run-report.json
```

## Cấu trúc

```text
test-data/
├── manifest.json        tóm tắt bộ dữ liệu + tổng hợp số liệu ngày
├── cases/               21 case: input + expected output + giải thích bẫy
├── evidence/            ảnh chuyển khoản, hóa đơn, nền tiếng ồn
├── score.py             chấm điểm tự động
├── audio_scripts.md     kịch bản đã dùng để thu 4 file audio
├── mix_noise.sh         trộn giọng đã thu với nền ồn ở SNR cố định
├── gen_noise.sh         sinh lại nền tiếng ồn
├── tts_openai.py        phương án dự phòng: sinh giọng bằng OpenAI TTS
├── generators/          script sinh lại toàn bộ ảnh + case (để mở rộng bộ test)
└── runs/                một thư mục con cho mỗi lần chạy eval
    ├── example-flawed-run/        ví dụ report khi AI mắc lỗi điển hình
    └── 2026-09-11-old-backend/    baseline 11/21 trên backend cũ (chỉ report.md)
```

---

## Phân bổ 21 case

| Loại | Số case | Case |
|---|---|---|
| TEXT | 6 | T1–T6 |
| AUDIO | 4 | A1–A4 |
| IMAGE_RECEIPT | 3 | R1–R3 |
| IMAGE_TRANSFER | 7 | M1–M7 |
| CLOSE_DAY | 1 | D1 |

Mật độ dồn vào IMAGE_TRANSFER vì ghép/phân loại tiền vào là hero use case.

### Các bẫy được gài có chủ đích

| Case | Bẫy |
|---|---|
| T2 | Không nói hình thức thanh toán → phải ra `UNKNOWN`, không đoán `CASH` |
| T4 | Chủ hộ bỏ tiền vào quỹ → `OWNER_MONEY`, **không phải** doanh thu |
| T6 | "1 triệu 250" → 1.250.000, không phải 250.000 |
| A2 | Giọng miền Trung thật ("o", "o nớ") + tiếng ồn nền SNR 12dB |
| A3 | Nói vấp tự sửa giữa câu → lấy số **chốt cuối**, không lấy số nghe đầu |
| A4 | Không có nghiệp vụ, nhưng câu có chứa số → không được bịa giao dịch |
| R2 | Hóa đơn in mờ, có cả tiền khách đưa (200.000) và tiền thối (15.000) → phải lấy **tổng 185.000** |
| R3 | Ảnh nhãn sản phẩm, không phải chứng từ → không tạo event |
| M1–M6 | **Bẫy tên**: ảnh khách chụp màn hình chuyển đi, tên hiển thị là **chủ shop** |
| M3 | 600.000 khớp 2 đơn cùng lúc → phải trả đủ 2 candidate, **không tự ghép** |
| M4 | Không khớp đơn nào, memo có "COC" → đặt cọc, doanh thu không đổi |
| M6 | 5 triệu chủ hộ tự chuyển → `OWNER_MONEY`, rất dễ bị nhầm thành doanh thu |
| M7 | Lệch 8.000 do phí ngân hàng → không được tự ghép |

### Bẫy tên — vì sao tách thành trục chấm riêng

Ở hộ kinh doanh Việt Nam, cách phổ biến nhất để chứng minh đã thanh toán là
**khách chụp màn hình chuyển khoản thành công trên máy mình rồi gửi cho chủ shop**.
Trên ảnh đó, tên hiển thị là **người nhận — tức chủ shop**, còn tên khách chỉ
xuất hiện trong "Lời nhắn" (nếu có).

Nghĩa là AI lấy tên trên màn hình làm `counterparty` sẽ **luôn** ra tên chủ shop,
với mọi giao dịch, và việc ghép theo tên sẽ hỏng hoàn toàn. 6/7 ảnh trong bộ này
theo đúng kiểu đó; riêng M7 là ảnh biến động số dư chụp từ máy chủ shop, khi đó
tên hiển thị mới đúng là khách. `score.py` đo riêng tỉ lệ dính bẫy này.

---

## Cách chấm

**Tự động** — critical field, khớp tuyệt đối, quyết định pass/fail:
`type`, `amount`, `paymentMethod`, `paymentStatus` (event);
`direction`, `amount`, `status`, `classificationType` (money movement);
4 số tổng hợp + `warningCount` (D1).

**Chấm tay** — soft field, theo thỏa thuận của team: `description`, `counterparty`.
`score.py` xuất sẵn `human_grading.md` để đánh Đ/S, chấp nhận diễn đạt khác nếu
đúng ý (ví dụ "chị Lan" vs "Lan" đều được).

**Chỉ số riêng cho hero use case**: tỉ lệ top-1 đúng, tỉ lệ trả đủ candidate,
số lần tự ghép khi không được phép, tỉ lệ dính bẫy tên.

---

## Số liệu tổng hợp kỳ vọng (case D1)

| Chỉ tiêu | Giá trị |
|---|---|
| Doanh thu | 4.940.000 đ |
| Chi phí | 1.720.000 đ |
| Tiền đã thu | 2.620.000 đ |
| Còn phải thu | 2.320.000 đ |
| Warning OPEN | 2 (M7 chưa ghép, R2 còn DRAFT) |

**Khẳng định quan trọng nhất:** trong ngày có **6.130.000 đ tiền vào không phải
doanh thu** (đặt cọc 380.000 + khoản chưa rõ 250.000 + chủ hộ góp 5.000.000 +
tiền mặt chủ hộ bỏ vào quỹ 500.000). Nếu `revenue` vượt 4.940.000, gần như chắc
chắn một trong các khoản này đã bị tính nhầm thành doanh thu.

Các số trên được **tính tự động từ chính các case** (`generators/build_cases.py`
có assert nội bộ), nên không thể lệch khỏi dữ liệu.

---

## Trạng thái

✅ Ảnh chứng từ (10 file) — sinh xong
✅ Audio (4 file) — **đã thu bằng giọng người thật**
✅ A2 đã trộn nhiễu ở SNR 12dB (đo gated EBU R128, kiểm chứng lệch ≤0.1dB)
✅ Baseline trên backend cũ 11/09: 11/21 pass — `runs/2026-09-11-old-backend/report.md`
   (chỉ có report, không có `actual.json`); lỗi lặp đã thành rule ở plan backend §4.1
⬜ Chạy lại 21 case trên backend mới → `score.py`, so với baseline

### Biến thể của A2

File chấm chính thức là `synthetic_voice_A2.m4a` (SNR 12dB). Ngoài ra còn ba file
**không tính vào 21 case**, chỉ để dò ngưỡng gãy của ASR khi cần:

| File | Dùng để |
|---|---|
| `synthetic_voice_A2_clean.m4a` | bản thu gốc, trộn lại khi muốn đổi mức ồn |
| `synthetic_voice_A2_snr18.m4a` | ồn nhẹ |
| `synthetic_voice_A2_snr06.m4a` | rất ồn |

Muốn mức ồn khác: `./mix_noise.sh evidence/synthetic_voice_A2_clean.m4a <ra>.m4a <snr>`

## Quy tắc khi tune

- Gom case FAIL theo **nguyên nhân chung**, sửa prompt/logic theo nguyên nhân đó —
  không sửa lẻ từng case (tránh overfit vào test set).
- **Không sửa expected output để lách lỗi.** Bộ case giữ cố định qua các lần tune
  để so sánh accuracy trước/sau có ý nghĩa.
- Chỉ thêm case mới khi gặp tình huống thật chưa được phủ; thêm bằng cách sửa
  `generators/build_cases.py` rồi chạy lại, để D1 tự tính lại theo.
