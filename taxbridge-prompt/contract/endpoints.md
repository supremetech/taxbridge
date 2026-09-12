# Endpoints ↔ fixtures

`B` = cần `X-Session-Token: <token>`. Đường dẫn fixture tương đối với `fixtures/`.

| Method | Path | Auth | Request fixture | Response | Response fixture |
|---|---|---|---|---|---|
| GET | `/api/health` | — | — | `200 {"ok": true}` | — |
| GET | `/api/docs` | — | — | `200 text/html` Swagger UI | — |
| GET | `/api/openapi.yaml` | — | — | `200 application/yaml` | — |
| POST | `/api/register` | — | `register_request.json` | `201 Session` | `session.json` |
| POST | `/api/login` | — | `login_request.json` | `200 Session` | `session.json` |
| POST | `/api/logout` | B | — | `204` | — |
| GET | `/api/zalo-users/unlinked` | — | — | `200 ZaloUser[]` | `zalo_users_unlinked.json` |
| POST | `/api/zalo/webhook` | secret header | `zalo/webhook_*.json` | `200 {"ok": true}` | — |
| POST | `/api/captures` (TEXT) | B | `capture_text_request.json` | `200 CaptureResult` | `capture_result_event.json` |
| POST | `/api/captures` (multipart) | B | xem bên dưới | `200 CaptureResult` | `capture_result_event.json` / `capture_result_movement.json` / `capture_result_failed.json` / `capture_result_batch.json` (Phase 2 ①) |
| GET | `/api/events?status=` | B | — | `200 BusinessEvent[]` | `events.json` |
| GET | `/api/events/{id}` | B | — | `200 BusinessEvent` | `event.json` |
| PUT | `/api/events/{id}` | B | `event_update_request.json` (partial) | `200 BusinessEvent` | `event.json` (đã cập nhật) |
| POST | `/api/events/{id}/confirm` | B | body rỗng | `200 BusinessEvent` | `event.json` với `status: CONFIRMED` (vẫn `UNPAID`; `PAID` chỉ sau match) |
| POST | `/api/events/{id}/reject` | B | body rỗng | `200 BusinessEvent` | — (`status: REJECTED`) |
| GET | `/api/money-movements?status=` | B | — | `200 MoneyMovement[]` | `money_movements.json` |
| GET | `/api/money-movements/{id}` | B | — | `200 MoneyMovement` | `money_movement.json` / `money_movement_unmatched.json` |
| POST | `/api/money-movements/{id}/match` | B | `match_request.json` | `200 MoneyMovement` | `money_movements.json[0]` |
| POST | `/api/money-movements/{id}/classify` | B | `classify_request.json` | `200 MoneyMovement` | `money_movement_classified.json` |
| GET | `/api/dashboard?date=YYYY-MM-DD` | B | — | `200 Dashboard` | `dashboard.json` |
| POST | `/api/close-day` | B | `close_day_request.json` | `200 DailyRecord` (upsert) | `daily_record.json` |
| GET | `/api/daily-records` | B | — | `200 DailyRecord[]` mới nhất trước | `daily_records.json` |
| GET | `/api/daily-records/{date}` | B | — | `200 DailyRecord` | `daily_record.json` |
| GET | `/api/reports?from=&to=` | B | — | `200 Report` (Phase 2 ④) | `report.json` |
| GET | `/api/pending` | B | — | `200 Pending` (Phase 2 ③a) | `pending.json` |
| POST | `/api/zalo-users/{zaloId}/replay` | B | body rỗng | `200 ReplayResult` (Phase 2 ③b) | `replay_result.json` |

Query filter: `status` optional; bỏ qua = tất cả. List sắp xếp `occurredAt` giảm dần.

`GET /api/dashboard` (Phase 2 ③a) có thêm `pastDraftCount`, `pastUnmatchedCount` = số DRAFT /
UNMATCHED có ngày **< `date`** (tồn đọng các ngày trước). `GET /api/reports`: `from`, `to` bắt
buộc, `to ≥ from`, tối đa 92 ngày; `byDay` chỉ gồm ngày có ≥ 1 event hoặc movement, mới nhất
trước; `byType` = CONFIRMED gộp theo `BusinessEvent.type`. `GET /api/pending`: `draftEvents` +
`unmatchedMovements` **mọi ngày**, `occurredAt` **tăng dần** (cũ nhất trước), movement kèm `candidates`.

`PUT /api/events/{id}` chỉ nhận: `type, amount, description, counterparty,
paymentMethod, paymentStatus, occurredAt`; field khác (kể cả `evidenceText`/`evidenceUrl`) → `400`. Chỉ sửa được khi
`status = DRAFT`, ngược lại `409 INVALID_STATE`.

## Multipart `POST /api/captures`

Đúng hai field: `type` (`AUDIO | IMAGE_RECEIPT | IMAGE_TRANSFER | IMAGE_BANK_HISTORY`) và `file`.
Ảnh JPEG/PNG ≤ 10 MB; audio M4A ≤ 10 MB, ≤ 60 giây. `IMAGE_BANK_HISTORY` (Phase 2 ①) → AI trả
nhiều dòng → N movement, `resultType: MONEY_MOVEMENT_BATCH`, `resultIds`, `skippedCount` (dòng
trùng movement đã có: cùng `direction + amount + ngày` + memo trùng token). 0 dòng đọc được →
`FAILED UNRECOGNIZED_IMAGE`; đọc được nhưng trùng hết → `DONE`, `resultIds: []`.

```bash
B=https://<api-base>; T=$(jq -r .token fixtures/session.json)

curl -s "$B/api/captures" -H "X-Session-Token: $T" \
  -H 'Content-Type: application/json' -d @fixtures/capture_text_request.json

curl -s "$B/api/captures" -H "X-Session-Token: $T" \
  -F type=IMAGE_RECEIPT -F file=@assets/demo/receipt.jpg

curl -s "$B/api/captures" -H "X-Session-Token: $T" \
  -F type=IMAGE_TRANSFER -F file=@assets/demo/transfer_deposit.jpg

curl -s "$B/api/captures" -H "X-Session-Token: $T" \
  -F type=AUDIO -F file=@assets/demo/sale_voice.m4a

curl -s "$B/api/captures" -H "X-Session-Token: $T" \
  -F type=IMAGE_BANK_HISTORY -F file=@assets/demo/bank_history.jpg      # Phase 2 ①

curl -s "$B/api/reports?from=2026-09-06&to=2026-09-12" -H "X-Session-Token: $T"   # Phase 2 ④
curl -s "$B/api/pending" -H "X-Session-Token: $T"                                  # Phase 2 ③a
curl -s -X POST "$B/api/zalo-users/$ZALO_ID/replay" -H "X-Session-Token: $T"       # Phase 2 ③b
```

## Zalo webhook giả (simulator)

```bash
curl -s "$B/api/zalo/webhook" \
  -H "X-Bot-Api-Secret-Token: $ZALO_WEBHOOK_SECRET" \
  -H 'Content-Type: application/json' -d @fixtures/zalo/webhook_text.json

curl -s "$B/api/zalo/webhook" -H "X-Bot-Api-Secret-Token: $ZALO_WEBHOOK_SECRET" \
  -H 'Content-Type: application/json' -d @fixtures/zalo/webhook_image.json

curl -s "$B/api/zalo/webhook" -H "X-Bot-Api-Secret-Token: $ZALO_WEBHOOK_SECRET" \
  -H 'Content-Type: application/json' -d @fixtures/zalo/webhook_voice.json

# body rỗng (probe) → vẫn 200
curl -s -X POST "$B/api/zalo/webhook" -H "X-Bot-Api-Secret-Token: $ZALO_WEBHOOK_SECRET"
```

Kịch bản UC8 → UC9 bằng simulator: gửi `webhook_text.json` khi `zaloId` chưa link →
`GET /api/zalo-users/unlinked` phải có user đó → `POST /api/register` với `zaloId` →
gửi lại `webhook_text.json` → `GET /api/events?status=DRAFT` có draft mới.

## Thứ tự smoke 9 UC

```text
UC1  register → session.token
UC2  captures TEXT → event DRAFT → PUT → confirm → dashboard.revenue +450k, receivable +450k
UC3  captures AUDIO (sale_voice.m4a) → event DRAFT → confirm
UC4  captures IMAGE_TRANSFER (450k) → movement + candidate → match → collected +450k, receivable −450k, bankIn +450k
UC5  captures IMAGE_TRANSFER (380k) → unmatched → classify DEPOSIT → revenue không đổi, unmatchedMoneyCount −1
UC6  captures IMAGE_RECEIPT (220k) → PURCHASE DRAFT → confirm → expense +220k
UC7  close-day → daily record có warning → xử lý → GET daily-records/{date}: warning RESOLVED, summary mới
UC8  zalo webhook (chưa link) → zalo-users/unlinked có user
UC9  zalo webhook (đã link, text/image/voice) → events hoặc money-movements có bản ghi mới
```

## Thứ tự smoke Phase 2 (UC10–14, `requirements-phase2.md` §3)

```text
UC10 captures IMAGE_TRANSFER (transfer_deposit.jpg) → movement.occurredAt bắt đầu "2026-09-11"
     → dashboard?date=2026-09-11 bankIn +380k → daily-records/2026-09-11 có warning UNMATCHED_MONEY mới
     (record đã tồn tại từ seed) → classify DEPOSIT → warning RESOLVED, summary.revenue không đổi
UC11 zalo webhook (đã link) → capture DONE; log có "sendMessage → ok" (token rỗng: log "bỏ qua reply")
UC12 reports?from=<D-6>&to=<D> → summary.revenue = Σ byDay[].revenue; byDay có dòng D
UC13 pending → draftEvents/unmatchedMovements có bản ghi ngày < D; dashboard?date=D có pastDraftCount ≥ 1
     → confirm → pending giảm 1. register với zaloId có message cũ → replay → replayed = n, events có draft ZALO
UC14 captures IMAGE_BANK_HISTORY (bank_history.jpg) → resultType MONEY_MOVEMENT_BATCH, len(resultIds) = 3,
     skippedCount = 2 → gửi lại cùng ảnh → resultIds = [], skippedCount = 5
```
