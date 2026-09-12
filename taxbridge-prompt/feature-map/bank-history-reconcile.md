# Đối soát lịch sử chuyển khoản ngân hàng

Chủ hộ chụp màn hình danh sách giao dịch trong app ngân hàng; app đọc mọi dòng, bỏ dòng đã có
trong sổ, tạo các khoản tiền vào/ra mới rồi mở màn **Đối soát** để ghép từng khoản với đơn bán
hoặc phân loại — không tự ghép (Phase 2 ①). DTO: `capture_result_batch.json`; backend: plan BE §15;
app: plan FE §13.

## Sub-features

- `history-extract` `IMAGE_BANK_HISTORY` → AI trả nhiều dòng, mỗi dòng có ngày (②).
- `history-dedupe` bỏ dòng trùng movement đã có (`direction + amount + ngày` + memo trùng token) → `skippedCount`.
- `history-batch-result` `resultType: MONEY_MOVEMENT_BATCH`, `resultIds[]`; 0 dòng → `FAILED`; trùng hết → `DONE`, `resultIds: []`.
- `reconcile-screen` mỗi movement mới: candidate tốt nhất + **Ghép** / **Phân loại**; chạm → Movement Detail.
- `reconcile-done` **Xong** → Home của ngày mới nhất trong batch.

## How to get to it (user POV)

- Home → **Đối soát lịch sử chuyển khoản** → **Dùng file demo** (`bank_history.jpg`) → **Gửi** →
  Đối soát `3 giao dịch mới (2 dòng đã có)` → dòng 1.200.000đ **Ghép** → dòng 250.000đ **Phân loại** →
  **Đặt cọc** → dòng 2.000.000đ ↗ **Phân loại** → **Khác** → **Xong** → Home 11/09.
- Gửi lại cùng ảnh → SnackBar `Không có giao dịch mới (5 dòng đã có trong sổ)`.

## Handles

| Màn hình | Loại | Nhãn |
|---|---|---|
| Home | nút | `Đối soát lịch sử chuyển khoản` |
| Capture (history) | nút | `Dùng file demo`, `Gửi` |
| Capture (history) | SnackBar | `Không có giao dịch mới (n dòng đã có trong sổ)` |
| Đối soát | tiêu đề | `Đối soát n giao dịch mới`, phụ đề `(m dòng đã có)` |
| Đối soát | nút | `Ghép`, `Phân loại`, `Xong`; sheet: `Đặt cọc`, `Tiền cá nhân`, `Khác`, `Không rõ` |
| Đối soát | dòng | `Có thể là: <description> - <amount>`, `Chưa rõ là khoản gì.` |

## Driving it with curl

Preconditions: như `match-classify-money.md`, đã chạy xong UC4 (`M1` MATCHED 450k) và UC5
(`M2` CLASSIFIED 380k) cùng ngày `$D0`; có SALE CONFIRMED UNPAID 1.200.000đ counterparty "chị Huệ"
ngày 10/09 (`curl … captures TEXT "hôm kia bán chị Huệ 2 hộp collagen 1 triệu 2 ck"` → confirm);
`demo-assets/bank_history.jpg` (5 dòng: +450k `LAN 3HOP` 11/09, +380k `COC MINH` 11/09,
+1.200k `HUE 2 COLLAGEN` 10/09, +250k `THAO 1HOP` 11/09, −2.000k `TRA TIEN HANG` 10/09).

- **Batch lần đầu.** `curl -s $B/api/captures -H "$H" -F type=IMAGE_BANK_HISTORY -F file=@demo-assets/bank_history.jpg`
  → `status: DONE`, `resultType: MONEY_MOVEMENT_BATCH`, `resultId: null`, `len(resultIds) == 3`,
  `skippedCount: 2`, `occurredAt` bắt đầu `2026-09-11`.
- **Movement mới đúng shape.** Với mỗi id: `curl -s $B/api/money-movements/$ID -H "$H"` → `captureType:
  IMAGE_BANK_HISTORY`, `evidenceUrl` là ảnh danh sách (cùng URL cho cả 3), `occurredAt` = ngày trên dòng;
  dòng 1.200k có `candidates[0].amount == 1200000`; dòng 2.000k `direction: OUT`, `candidates: []`.
- **Dashboard theo ngày.** `dashboard?date=2026-09-10` `bankIn` +1.200.000 (OUT không tính),
  `unmatchedMoneyCount` +2; `dashboard?date=$D0` `bankIn` +250.000.
- **Gửi lại → trùng hết.** Cùng lệnh → `DONE`, `resultIds: []`, `skippedCount: 5`, không movement mới.
- **Ghép / phân loại dùng API v1.** `match` dòng 1.200k với event chị Huệ → event `PAID`;
  `classify` 2 dòng còn lại → `pending` không còn 3 movement này.
- **Ảnh không phải danh sách.** Gửi `receipt.jpg` với `type=IMAGE_BANK_HISTORY` → `FAILED`, `error: UNRECOGNIZED_IMAGE`.
- **Đối chiếu trên app.** Simulator: nút `Đối soát lịch sử chuyển khoản` → `Dùng file demo` → `Gửi` →
  `inspect` tiêu đề `Đối soát 3 giao dịch mới`; sau 3 thao tác, 3 dòng có chip trạng thái; `Xong` →
  Home `Thứ Sáu, 11/09/2026`.
