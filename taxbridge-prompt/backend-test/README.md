# backend-test — đo độ chính xác xử lý back-end

Black-box qua REST. Khác `../test-data/` (đo AI trích xuất), bộ này đo **logic tất định**:
candidate, ghép/phân loại tiền, dashboard, đóng ngày. Ý đồ từng scenario: `test-plan.md`.

## Chạy

```bash
cd backend-test
python3 run.py --dry-run                              # validate JSON, không gọi mạng
python3 run.py --only SC-DASH --out runs/smoke        # rẻ nhất, không dùng ảnh (~40 s)
python3 run.py --out runs/2026-09-12-baseline         # cả 4 scenario (~6 phút)
python3 score.py runs/2026-09-12-baseline             # → report.md + run-report.json
```

Không cần biến môi trường nào cho 4 scenario hiện có. `--base` để đổi sang local
(`--base http://127.0.0.1:8787`); mặc định là Functions prod. Nhóm `ZALO` (chưa làm) sẽ cần
`ZALO_WEBHOOK_SECRET`.

Chỉ dùng thư viện chuẩn của Python 3 — không cài gì thêm.

## Bộ test tự dựng dữ liệu

Mỗi variation đăng ký **một account mới** (`tbtest_<runId>_<label>`, mật khẩu `123456`) nên
kỳ vọng là giá trị tuyệt đối và không đụng account demo. Danh sách account của mỗi vòng nằm
ở `runs/<vòng>/accounts.json` — **không có API xóa**, dọn tay nếu cần.

Event tất định được dựng bằng macro `seedEvent`: capture TEXT một câu cực dễ → `PUT` ép đúng
7 field cho phép → `confirm`/`reject`/để `DRAFT`. Movement thì không có `PUT`, nên số tiền do
AI đọc ảnh: capture **trước**, lưu số thật vào `${AMT}`, rồi mới seed event theo `${AMT}`.

## Đọc report

| Verdict | Nghĩa |
|---|---|
| ✅ `PASS` | mọi assertion đạt |
| ❌ `FAIL` | **back-end sai** |
| ⛔ `BLOCKED` | seed hỏng vì AI đọc lệch — **không tính vào điểm back-end**, không phải lỗi backend |
| 💥 `ERROR` | sự cố hạ tầng (mạng, register lỗi) |
| 🔎 `PROBE` | spec chưa định nghĩa: chỉ ghi nhận hành vi thật, không chấm pass/fail |

Con số quan trọng nhất là `backendAccuracy` (đã loại BLOCKED) và ba con số phải bằng 0:
`wrongAutoMatchCount`, `revenueInvarianceViolations`, `illegalTransitionSucceeded`.

## Viết thêm scenario

Một file JSON trong `scenarios/`, tự được `run.py` nạp. Cấu trúc:

```json
{
  "scenarioId": "SC-XXX", "title": "...", "intent": "ý đồ test, vì sao rule này quan trọng",
  "ruleRefs": ["..."], "isolation": "perVariation",
  "variations": [{
    "variationId": "V1-...", "mode": "assert",
    "act": [
      {"id": "up", "capture": {"type": "IMAGE_TRANSFER", "evidence": "M1"}, "save": {"movId": "$.resultId"},
       "precheck": [{"path": "status", "op": "eq", "value": "DONE", "onFail": "block", "why": "AI hỏng"}]},
      {"id": "ev", "seedEvent": {"type": "SALE", "amount": "${AMT}", "confirm": true}},
      {"id": "mov", "call": "GET /api/money-movements/${movId}"}
    ],
    "expect": [{"rule": "CAND-NO-AUTO", "target": "mov", "path": "matchedEventId", "op": "isNull"}]
  }]
}
```

- `rule` phải có trong `rules.json` (severity + hero + trích dẫn spec) — `--dry-run` kiểm.
- Biến: `${today}` `${today-1}` `${today+1}` · `${<stepId>}` (id event từ `seedEvent`) ·
  `${AMT}` `${AMT-1}` `${-AMT}` (từ `save`) · `${evidence.M1.amount}` · `${env.TEN_BIEN}`.
- `target`: `<stepId>` (lấy body) · `<stepId>.status` · `<stepId>.ms`.
- `path`: `a.b` · `candidates[0].score` · `candidates[*].eventId` · `warnings[?resourceId=ev_1].status`.
- `op`: `eq neq isNull notNull approx len contains notContains monotonicDesc sameAs
  differsFrom delta diffOnlyKeys`.
- **Luật bất di bất dịch**: giá trị do AI sinh (số tiền đọc từ ảnh, memo, counterparty) chỉ
  được dùng trong `precheck`, không bao giờ trong `expect`. Nếu không, bộ test lại đi đo AI.

## Quy tắc khi có FAIL

Lệch giữa test và spec thì **sửa spec hoặc sửa code**, không sửa `expect` cho qua. Nếu spec
chưa định nghĩa thì chuyển variation sang `mode: "probe"` và ghi vào mục "hành vi chưa định
nghĩa" của report để team chốt.
