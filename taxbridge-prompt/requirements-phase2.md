# TaxBridge — Yêu cầu bổ sung Phase 2 (build day 12/09, sau 14:30 freeze v1)

Nguồn: `note.md` (5 dòng). File này là bản phân tích đã chốt với user 12/09 ~12:00; contract /
plan / feature-map đã cập nhật theo đây. Đọc file này khi cần biết **vì sao** một quyết định
được chọn; **làm gì** thì đọc plan.

Bối cảnh: v1 (9 UC) xong lúc ~11:45 (BE 86 pass prod, app chạy prod UC1–7). Phase 2 code
tiếp trong build day, ưu tiên theo giá trị demo / video; phần chưa xong lúc quay video thì cắt.

## 1. Thứ tự và phụ thuộc

```text
Phase 7   ② ngày trên chứng từ  ──┐  (tiền đề của ①③④: dữ liệu phải có ngày đúng)
          ⑤ Zalo reply           ─┘  (độc lập; IAM đã cấp 12/09 12:05 → chỉ còn code)
Phase 8   ④ báo cáo theo khoảng   ──┐  (đọc thuần, không đụng pipeline)
          ③ tồn đọng + replay Zalo ─┘
Phase 9   ① đối soát lịch sử CK        (lớn nhất: type mới, AI trả mảng, dedupe, màn mới, ảnh demo mới)
```

Cut line: xong Phase 7 là video có thêm 2 điểm (bot trả lời trong Zalo + sổ ghi đúng ngày).
Phase 8 làm được ④ trước ③. Phase 9 chỉ bắt đầu nếu còn ≥ 1 h trước lúc quay.

## 2. Quyết định từng yêu cầu

### ② "Đổi lại ghi nhận thông tin theo ngày trên hoá đơn" → `doc-date`

| | Chốt |
|---|---|
| Phạm vi | `IMAGE_RECEIPT`, `IMAGE_TRANSFER`, ảnh Zalo (`IMAGE_UNKNOWN`) và `IMAGE_BANK_HISTORY` (①): AI đọc ngày in trên chứng từ. Text / voice: chỉ khi người nói nêu rõ ("hôm qua", "sáng 10/9"); không nói → `now()`. |
| Fallback | Không đọc được, sai format, > hôm nay + 1 ngày, hoặc < hôm nay − 365 ngày → `now()`. Ảnh có ngày không có giờ → `12:00:00+07:00`. |
| Ảnh demo | **Không render lại.** 3 ảnh demo in `11/09/2026` → event/movement demo rơi vào ngày 11/09 (đã seed daily record). Vì vậy: Home có **chọn ngày**; sau mutation app về Home **của ngày bản ghi**, không phải hôm nay → hero `Tiền vào +380.000đ · Doanh thu không đổi ✓` vẫn hiện. |
| Sổ ngày đã đóng | Bản ghi mới rơi vào ngày đã có `daily_records/{date}` → backend `sync_record(date)` recompute `summary` + thêm warning mới ngay lúc tạo. `resolve_warnings` cũ gộp vào `sync_record`. |
| Sửa tay | Event Detail thêm ô **Ngày** (PUT `occurredAt` đã cho phép từ v1). Đổi ngày → sync cả ngày cũ lẫn ngày mới. |
| Bỏ | Rule "không đọc ngày giờ trên ảnh" ở CLAUDE.md §6, plan BE §4.1, prompt. |

Đảo một quyết định có chủ đích của v1 (plan BE §4.1 giải thích lý do cũ). Lý do đổi: hộ kinh
doanh chụp hoá đơn / ảnh CK dồn cuối ngày hoặc hôm sau — ghi `now()` là sai sổ.

### ⑤ "Phản hồi lại Zalo khi nhận được tin nhắn" → `zalo-reply`

| | Chốt |
|---|---|
| API | `POST https://bot-api.zapps.me/bot{ZALO_BOT_TOKEN}/sendMessage` JSON `{chat_id, text}` (kiểu Telegram; xác nhận qua SDK python-zalo-bot / zalo-bot-sdk 12/09). `chat_id` = `chatId` đã normalize. Response shape ghi lại vào contract §6 sau lần gọi thật đầu tiên. |
| Khi nào | Sau mọi message có người gửi: chưa link / DONE EVENT / DONE MOVEMENT / FAILED. Sticker & OTHER: không reply. |
| Ở đâu | Trong request webhook, **trước khi trả 200** (Functions gen2 đóng băng CPU sau response). Lỗi sendMessage → log, vẫn 200. |
| Secret | `ZALO_BOT_TOKEN` thêm lại vào `secrets=[...]` `main.py`. IAM đã cấp 12/09: `roles/secretmanager.secretAccessor` cho `495996584842-compute@developer.gserviceaccount.com`. Local: `.env` root. Token rỗng → bỏ qua reply (emulator / smoke). |
| Không làm | Lệnh hai chiều ("ok" để confirm, "sửa 450 thành 500"). Ghi backlog. |

### ④ "Tổng hợp doanh thu, giao dịch theo khoảng thời gian" → `report-range`

| | Chốt |
|---|---|
| API | `GET /api/reports?from=YYYY-MM-DD&to=YYYY-MM-DD` → `Report` (contract). Cả hai bắt buộc, `to ≥ from`, tối đa 92 ngày (`400 VALIDATION_ERROR`). |
| Tính | Đọc `events` + `money_movements` của business, lọc `occurredAt` trong `[from, to]`, tính trong Python như dashboard. `summary` (5 số + đếm), `byDay` (chỉ ngày có dữ liệu, mới nhất trước), `byType` (CONFIRMED theo `BusinessEvent.type`). Không ledger, không index. |
| App | Màn **Báo cáo**: chip `Hôm nay · 7 ngày · Tháng này · Tháng trước · Tùy chọn`; `SummaryGrid` + Thuế khoán ước tính cả kỳ; danh sách theo ngày, chạm → Home ngày đó. |

### ③ "Xử lý giao dịch chưa được xử lý trong quá khứ" → `pending-backlog` + `zalo-replay`

Hiểu theo 3 nghĩa, làm 2:

| | Chốt |
|---|---|
| (a) Tồn đọng | `GET /api/pending` → mọi `DRAFT` event + `UNMATCHED` movement **mọi ngày**, cũ nhất trước, kèm `byDate`. `Dashboard` thêm `pastDraftCount`, `pastUnmatchedCount` (ngày < `date` đang xem). Home: dòng cảnh báo + nút **Tồn đọng** (badge) → màn nhóm theo ngày, chạm → detail v1 (confirm/reject/match/classify dùng lại). |
| (b) Zalo trước khi link | `POST /api/zalo-users/{zaloId}/replay` (auth; zaloId phải link với account gọi). Chạy `process_capture` cho `zalo_unlinked_messages` TEXT/IMAGE/AUDIO chưa `replayedAt`; media URL Zalo có thể hết hạn → capture FAILED, đếm `failed`. App gọi ngay sau register có `zaloId`, SnackBar "Đã xử lý n tin nhắn Zalo cũ". Bỏ mục "không xử lý lại message Zalo cũ" khỏi CLAUDE.md §4. |
| (c) Retry capture FAILED | **Không làm** (PoC). |

### ① "Đối soát lịch sử chuyển khoản ngân hàng" → `bank-history`

| | Chốt |
|---|---|
| Đầu vào | **Ảnh chụp màn hình danh sách giao dịch** trong app ngân hàng / sao kê (vision), capture type mới `IMAGE_BANK_HISTORY`. CSV/Excel: không làm. |
| AI | `BankHistoryExtraction {transfers: TransferExtraction[]}`; mỗi dòng có `occurredDate` (②). Dòng không có số tiền / dòng số dư → bỏ. `+` / "nhận" → IN; `−` / "chuyển đi" → OUT. Không dòng nào → `FAILED UNRECOGNIZED_IMAGE`. |
| Trùng lặp | **Bắt buộc** (khác v1 §4): bỏ dòng có movement cùng `direction + amount + ngày` và memo trùng token (hoặc cả hai memo rỗng). Đếm `skippedCount`. Chỉ áp dụng cho batch; ảnh CK đơn lẻ vẫn không dedupe. |
| Kết quả | `CaptureResult.resultType = MONEY_MOVEMENT_BATCH`, `resultIds[]`, `skippedCount`. Mỗi movement: `captureType=IMAGE_BANK_HISTORY`, `evidenceUrl` = ảnh danh sách. |
| Đối soát | Màn **Đối soát**: N movement mới, mỗi dòng candidate tốt nhất (`candidates_for` v1) + **Ghép** / **Phân loại** (sheet 4 nút). **Không auto-match** — người dùng quyết. |
| Ảnh demo | `demo-assets/bank_history.jpg` mới (5 dòng, ≥ 2 trùng ảnh CK đã chụp, 1 OUT) — làm trong Phase 9, cùng script AppKit đã dùng cho 3 ảnh v1. |
| Eval | Thêm case `test-data/` cho ngày chứng từ (R/M) + bank history: **sau build day**. |

## 3. UC mới (số phải đúng; bổ sung §9 CLAUDE.md)

| UC | Hành động | Kỳ vọng |
|---|---|---|
| 10 | Ảnh CK 380k `COC MINH` (in 11/09) | movement `occurredAt` = `2026-09-11T11:02:00+07:00`; app về Home **11/09**: `bankIn` +380k, banner hero; `daily_records/2026-09-11` có warning mới `UNMATCHED_MONEY` |
| 11 | Zalo user đã link nhắn "bán 2 hộp collagen 300k ck" | bot trả lời trong Zalo `✅ Đã ghi nháp: Bán hàng 300.000đ …`; user chưa link nhắn → bot hướng dẫn liên kết |
| 12 | Báo cáo `7 ngày` | `summary.revenue` = Σ SALE CONFIRMED 06–12/09; `byDay` có dòng 11/09 = `dashboard(11/09).revenue` |
| 13 | Còn draft 180k ngày 11/09, đang xem Home 12/09 | Home: `Còn 1 giao dịch chưa xử lý từ các ngày trước` → Tồn đọng → confirm → Home 11/09 `revenue` không đổi (PURCHASE) `expense` +180k; register với zaloId có 2 message cũ → SnackBar `Đã xử lý 2 tin nhắn Zalo cũ`, 2 draft mới |
| 14 | Ảnh `bank_history.jpg` sau khi đã chụp UC4/UC5 | `resultIds` = 3, `skippedCount` = 2; màn Đối soát 3 dòng; Ghép 1 → `collected` tăng; phân loại 2 |

## 4. Backlog (không làm build day)

- Lệnh hai chiều qua Zalo; retry capture FAILED; CSV sao kê; export báo cáo; eval case mới.
