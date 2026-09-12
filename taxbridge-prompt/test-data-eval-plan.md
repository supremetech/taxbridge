# TaxBridge — Kế hoạch bộ Test Data đánh giá & tune AI Extraction (PoC)

_Trạng thái 11/09/2026: bộ dữ liệu **đã sinh** — 21 case, ảnh, audio giọng thật, `score.py`,
tất cả ở `test-data/`. Nguồn sự thật về danh sách case, format ground truth, cấu trúc thư mục
và cách chạy là `test-data/README.md`. File này chỉ giữ lý do thiết kế và quy tắc tune._

Baseline trên backend cũ: **11/21 pass**, `test-data/runs/2026-09-11-old-backend/report.md`.
Các lỗi lặp (bẫy tên chủ shop trên ảnh khách chụp, không nói hình thức thanh toán → `UNKNOWN`,
"1 triệu 250", tự sửa khi nói, tiền thối trên hóa đơn) đã thành rule prompt ở
`implement-plan-backend-poc.md` §4.1, đánh dấu *(eval …)*.

---

## 0. Đối chiếu phạm vi với PoC hiện tại

Skill `taxbridge-test-data` mặc định theo spec đầy đủ của TaxBridge/Sổ Quầy:
entity `SourceEvent/LedgerEntry/ReconciliationCase`, ~11 mã ngoại lệ đối soát,
hệ thống tài khoản ledger, test cross-tenant, test prompt-injection ở quy mô
eval production. PoC hiện tại (theo `implement-plan-backend-poc.md`,
`implement-plan-flutter-poc.md`, `CLAUDE.md`) đơn giản hơn nhiều: chỉ có
`Capture / BusinessEvent / MoneyMovement / DailyRecord`, không có ledger, chỉ
2 loại warning (`UNMATCHED_MONEY`, `DRAFT_EVENT`).

Kế hoạch này **thu hẹp** taxonomy của skill về đúng những gì AI/backend PoC
thực sự phải quyết định đúng — bỏ ledger double-entry, cross-tenant, và test
prompt-injection formal (không cần cho mục tiêu "tune độ chính xác extraction"
lúc này) — nhưng vẫn giữ tinh thần "gài bẫy có chủ đích" thay vì tạo giao dịch
sạch chung chung.

---

## 1. Nguyên tắc bộ test

```text
Phạm vi thời gian: 1 ngày mô phỏng (đủ để test cả luồng đóng ngày).
Số lượng: 21 case — nhỏ, nhưng mỗi case chọn có chủ đích để phủ một
  nhánh quyết định cụ thể của AI (không phải giao dịch ngẫu nhiên).
Mỗi case = 1 input (text/audio/ảnh) + 1 expected output đi kèm ngay cạnh,
  để so sánh tự động, không cần người dùng chấm tay từng case.
Trọng tâm: matching tiền vào với sale + classify tiền chưa rõ — đây là
  hero use case, cần mật độ case dày nhất trong bộ.
Bộ case giữ cố định qua các lần tune (không sửa expected để né lỗi);
  chỉ thêm case mới khi phát hiện tình huống thật chưa được phủ.
```

---

## 2. Quy trình chấm điểm và tự cải tiến

```text
Bước 1 — Chạy thật: đưa từng case qua đúng pipeline AI của backend
  (process_capture), lưu actual output theo caseId.

Bước 2 — So khớp theo 2 mức:
  - Critical fields (bắt buộc khớp tuyệt đối để case được tính "đúng"):
      type / amount / paymentMethod / paymentStatus (event);
      direction / amount / status / classificationType (movement);
      4 số summary + warningCount (D1) — đúng như score.py
  - Soft fields (chấm nới lỏng, không quyết định pass/fail):
      description / counterparty / memo — chấp nhận diễn đạt khác nhau
      miễn đúng ý; occurredAt cho phép lệch nhỏ nếu không nói rõ giờ.

Bước 3 — Tính các chỉ số:
  - Field-level accuracy (%) theo từng field, theo từng loại capture.
  - Case-level pass/fail dựa trên critical fields.
  - Matching-specific: tỷ lệ top-1 đúng, tỷ lệ top-3 chứa candidate đúng
    (riêng cho các case IMAGE_TRANSFER có candidates).
  - Confusion matrix cho 2 trục quan trọng nhất:
      BusinessEvent.type (SALE/PURCHASE/DEPOSIT/OWNER_MONEY/UNKNOWN)
      MoneyMovement.classificationType (DEPOSIT/OWNER_MONEY/OTHER/UNKNOWN)

Bước 4 — Sinh report:
  - run-report.json: so sánh chi tiết từng case (actual vs expected).
  - report.md: accuracy tổng, top lỗi lặp lại nhiều nhất, case nào fail
    và vì field nào.

Bước 5 — Vòng lặp cải tiến:
  - Gom các lỗi có cùng nguyên nhân thành 1 "root-cause tag" thay vì sửa
    từng case riêng lẻ (ví dụ: "không lấy số tiền cuối khi người nói tự
    sửa", "bỏ qua gợi ý 'đặt cọc' trong memo khi chấm classify").
  - Sửa prompt/logic theo đúng root-cause đó.
  - Chạy lại **đúng bộ 21 case này** làm regression, so accuracy trước/sau.
  - Không sửa expected output để lách qua lỗi — chỉ thêm case mới khi có
    tình huống thật phát sinh mà bộ hiện tại chưa phủ.
```

---
