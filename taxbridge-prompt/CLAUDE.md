# CLAUDE.md — TaxBridge PoC

Hướng dẫn cho Claude Code khi làm việc trong monorepo `taxbridge/`.

## 1. Dự án

TaxBridge: agent ghi nhận giao dịch cho **hộ kinh doanh** Việt Nam qua text / giọng
nói / ảnh hóa đơn / ảnh chuyển khoản → AI tạo bản nháp → ghép tiền vào với đơn bán →
đóng ngày. PoC cho hackathon "Agents, Everywhere" (AI Tinkerers Đà Nẵng, build day
12/09/2026), demo 2 phút trên iPhone thật. Mục tiêu: **chạy end-to-end 9 use case v1 ở mục 9**
(xong 12/09 ~11:45), rồi **Phase 2 = UC10–14** (`requirements-phase2.md`, chiều 12/09), code ngắn,
dễ sửa. Không hardening, không production-ready.

Hero moment: chụp chuyển khoản 380k → app hỏi "khoản này là gì?" → chọn "Đặt cọc" →
**tiền vào ngân hàng tăng nhưng doanh thu không đổi**. Mọi quyết định UI/API phải giữ
được khoảnh khắc này.

## 2. Cấu trúc

```text
taxbridge/                          git · MONOREPO (một .git ở đây) · branch master
├── CLAUDE.md → taxbridge-prompt/CLAUDE.md   (symlink)
├── taxbridge-prompt/
│   ├── CLAUDE.md
│   ├── contract/                   README (quy ước/enum/error/Zalo) · endpoints.md · fixtures/*.json
│   ├── feature-map/                kịch bản kiểm chứng: 2 luồng hero v1 + 5 file Phase 2 (§3.4)
│   ├── implement-plan-backend-poc.md   §1–11 v1 · §12–17 Phase 2
│   ├── implement-plan-flutter-poc.md   §1–9 v1 · §10–14 Phase 2
│   ├── requirements-phase2.md      phân tích + quyết định 5 yêu cầu `note.md` → UC10–14
│   ├── test-data/                  bộ eval AI 21 case + score.py (README riêng); test-data-eval-plan.md = lý do thiết kế
│   ├── hackathon-prep-checklist.md   việc tối 11/09 · time-box build day (§4) · video script
│   └── demo-assets/                sale_voice.{m4a,aac} + receipt.jpg · transfer_match.jpg · transfer_deposit.jpg (+ bank_history.jpg Phase 2)
├── taxbridge-server/
│   └── functions/                  Python 3.12 · Flask · Firebase Functions gen2
└── taxbridge-app/
    └── lib/                        Flutter · Riverpod 3 · go_router · Dio
```

Một repo git duy nhất ở `taxbridge/` (12/09 gộp từ 3 repo); `git` chạy ở đâu trong cây cũng được.

## 3. Nguồn sự thật (theo thứ tự)

1. `contract/` — DTO, enum, endpoint, status/error code, fixtures, Zalo payload + remux.
   Đổi contract = sửa ở đây trước, rồi mới sửa code hai bên.
2. Plan backend: mục 2 (Firestore), 4 (capture/AI), 6–8 (movement, dashboard, close day),
   9 (Zalo); Phase 2: 12 (ngày), 13 (report), 14 (pending/replay), 15 (bank history), 16 (Zalo reply).
3. Plan Flutter: mục 3 (session/API), 6 (màn hình, hero), 7 (state); Phase 2: 10–13.
   `requirements-phase2.md` = **vì sao** chọn như vậy; không lặp DTO/endpoint.
4. `feature-map/` — kịch bản kiểm chứng end-to-end theo feature (handle UI + lệnh + bằng
   chứng), dùng **sau khi code** để đóng vòng. Không định nghĩa DTO/endpoint (contract) hay
   layout (plan Flutter §6); riêng **nhãn nút / ô nhập / chip** thì bảng `Handles` ở đây là chủ.

Sửa một quyết định → cập nhật cả hai plan; xong phase → tick `[x]`.

## 4. Phạm vi

**Làm (v1):** register/login (token) · text/voice/ảnh capture → AI draft · sửa/confirm draft ·
dashboard 7 số · ảnh chuyển khoản → money movement → match/classify · close day + lịch
sử + warning OPEN/RESOLVED · Zalo Bot webhook đi chung pipeline.

**Làm (Phase 2, `requirements-phase2.md`):** `occurredAt` = ngày in trên chứng từ (Home theo ngày,
sổ đã đóng tự đồng bộ) · bot trả lời trong Zalo · báo cáo theo khoảng ngày · tồn đọng mọi ngày +
replay message Zalo trước khi link · ảnh lịch sử CK → batch movement + dedupe + màn Đối soát.

**Không làm:** Firebase Auth, role/permission, multi-business, Security Rules, idempotency,
audit trail, ledger double-entry, offline sync, retry/backoff, duplicate detection (**trừ** batch
bank history), prompt-injection hardening, mask/redact, realtime Firestore ở app, App Check,
Crashlytics, dark mode, i18n, test coverage lớn, lệnh hai chiều qua Zalo, retry capture FAILED,
CSV sao kê, export báo cáo.

Yêu cầu rơi vào "không làm": nói rõ một câu, hỏi lại; user xác nhận thì làm nhưng vẫn
giữ phong cách PoC.

## 5. Contract — bất biến

Chi tiết ở `contract/README.md`; tóm tắt những gì không được vi phạm:

- Base `/api`, JSON `camelCase`, tiền **`int` VND**, thời gian ISO-8601 `+07:00`, ngày
  nghiệp vụ `Asia/Ho_Chi_Minh` dạng `YYYY-MM-DD`.
- Success trả thẳng DTO; error `{code, message}`. Mọi mutation trả DTO mới nhất.
- Header `X-Session-Token: <token>`; backend resolve `accountId`/`businessId` từ
  `sessions/{token}`; **client không bao giờ gửi `businessId`**. Public: `/api/health`,
  `/api/register`, `/api/login`, `/api/zalo-users/unlinked`, `/api/zalo/webhook`.
- Capture xử lý **đồng bộ**, trả `{captureId, status, resultType, resultId, resultIds, skippedCount,
  occurredAt, error}`; AI lỗi → HTTP 200 + `status: FAILED`, không 5xx.
- Phase 2 endpoint: `GET /api/reports?from&to`, `GET /api/pending`, `POST /api/zalo-users/{zaloId}/replay`.

Enum canonical (không tự thêm value ở bất kỳ bên nào):

```text
Capture.type:          TEXT | AUDIO | IMAGE_RECEIPT | IMAGE_TRANSFER | IMAGE_BANK_HISTORY   (+ IMAGE_UNKNOWN nội bộ backend, ảnh Zalo)
Capture.status:        PROCESSING | DONE | FAILED
Capture.resultType:    EVENT | MONEY_MOVEMENT | MONEY_MOVEMENT_BATCH
BusinessEvent.type:    SALE | PURCHASE | DEPOSIT | OWNER_MONEY | UNKNOWN
BusinessEvent.status:  DRAFT | CONFIRMED | REJECTED
paymentMethod:         CASH | BANK | UNKNOWN
paymentStatus:         UNPAID | PAID | UNKNOWN
MoneyMovement.status:  UNMATCHED | MATCHED | CLASSIFIED
classificationType:    DEPOSIT | OWNER_MONEY | OTHER | UNKNOWN
direction:             IN | OUT
Warning.type:          UNMATCHED_MONEY | DRAFT_EVENT
Warning.status:        OPEN | RESOLVED
Warning.resourceType:  EVENT | MONEY_MOVEMENT
source:                APP | ZALO                                   (event + movement)
captureType:           TEXT | AUDIO | IMAGE_RECEIPT | IMAGE_TRANSFER | IMAGE_BANK_HISTORY (event + movement)
```

## 6. Backend — rule phải giữ

Stack: Python 3.12 · Flask blueprint prefix `/api` · Firebase Functions gen2 · Firestore ·
Cloud Storage · OpenAI. File theo plan mục 1 (`app/*_service.py` + `app/routes/*.py`).

- Password: `werkzeug.security.generate_password_hash` / `check_password_hash`.
- Session: `sessions/{token}`, token `tb_` + `secrets.token_urlsafe(32)`, resolve trong
  `before_request` → `g.account_id` / `g.business_id`. Logout xóa doc.
- Text/voice/receipt → `events` DRAFT; transfer → `money_movements` UNMATCHED.
  `process_capture()` dùng chung cho app và Zalo. Bằng chứng: `evidenceText` (câu gốc /
  transcript) + `evidenceUrl` (Storage download URL có token, public với ai có link — chấp
  nhận PoC) copy từ capture lên event/movement; contract §5.1, plan BE §4.2.
- AI: `SALE` + "chuyển khoản" → `paymentMethod=BANK`, `paymentStatus=UNPAID`; chỉ `PAID`
  khi nói rõ đã nhận; không nói hình thức → `UNKNOWN`/`UNKNOWN`. "450 nghìn" = 450000,
  "1 triệu 2" = 1200000, "1 triệu 250" = 1250000, "300k" = 300000. Ảnh CK khách chụp: tên
  hiển thị là chủ shop → `counterparty` lấy từ nội dung CK. `occurredAt`: ảnh = ngày in trên
  chứng từ; text/voice chỉ khi nói rõ; còn lại now(); ngoài [now−365d, now+1d] → now()
  (Phase 2 ②, plan BE §12; v1 luôn now()). Đủ rule (đánh dấu *eval*) ở plan BE §4.1.
- Dashboard: `revenue` = CONFIRMED SALE; `expense` = CONFIRMED PURCHASE; `collected` =
  CONFIRMED SALE PAID; `receivable = revenue − collected`; **`bankIn` = mọi movement IN
  bất kể status**; `draftCount`; `unmatchedMoneyCount`. Tính khi đọc, không ledger.
- Match: movement `MATCHED` + event `paymentStatus=PAID`. Classify `DEPOSIT`/`OWNER_MONEY`
  **không** động vào revenue.
- Close day: upsert `daily_records/{date}` đúng shape DTO (nested `summary`). `sync_record(date)`
  sau mọi tạo / confirm / reject / match / classify / đổi ngày: record đã có → warning mới cho
  DRAFT/UNMATCHED, warning hết lý do → `RESOLVED` + `resolvedAt`, recompute `summary`; chưa đóng →
  không tạo.
- Phase 2: `reports` / `pending` tính trong Python từ cả collection; `IMAGE_BANK_HISTORY` dedupe
  theo `direction + amount + ngày` + memo trùng token (chỉ batch); bot reply gọi `sendMessage`
  **trước khi trả 200**, token rỗng → bỏ qua, không bao giờ raise.
- Zalo Bot Platform: payload, media URL public, voice `.aac` → remux `.m4a`
  (`imageio-ffmpeg`), body rỗng → 200, secret header, luôn trả
  200 — tất cả ở `contract/README.md` §6. Chưa link → `zalo_unlinked_messages` (replay sau khi
  link, §6.2); đã link → capture `source=ZALO`, ảnh = `IMAGE_UNKNOWN` (prompt trả `kind`).
  Reply theo bảng §6.1. Secret `ZALO_BOT_TOKEN` đã cấp IAM 12/09.
- Mọi việc xong **trước khi trả response** (upload Storage, gọi API…): Functions gen2
  đóng băng CPU sau response.
- OpenAI (pin trong `config.py`): vision/text **`gpt-5.6-terra`**, `reasoning.effort="low"`,
  Responses API `responses.parse` + Pydantic; audio **`gpt-transcribe`** với
  `languages=["vi"]` + `prompt`/`keywords` (không có param `language` số ít) rồi qua prompt
  extract như text. Fallback: vision `gpt-5.6-luna`; audio `gpt-4o-transcribe` `language="vi"`.
- Firestore: tránh `where` + `order_by` khác field (cần composite index, chỉ lộ lúc chạy);
  đọc collection của business rồi filter/sort trong Python.

Dev loop:

```bash
cd taxbridge-server/functions
gcloud auth application-default login && export GCLOUD_PROJECT=hackathon-42790
flask --app app.flask_app:create_app run --port 8787
ngrok http --domain=<static>.ngrok-free.app 8787
firebase deploy --only functions:api        # chỉ ở mốc, ~2 phút/lần
```

- `create_app()` tự gọi `firebase_admin.initialize_app()` với guard `if not firebase_admin._apps`
  để chạy được cả `flask run` lẫn Functions.
- Test tối thiểu: `tests/smoke/smoke.sh` chạy 9 UC bằng curl với fixtures trong
  `contract/`; cũng là Zalo simulator.

## 7. Flutter — rule phải giữ

Stack: Flutter · Material 3 · `flutter_riverpod ^3.4` · `go_router ^18` · `dio ^5.11` ·
`image_picker ^1.2` · `record ^7` · `shared_preferences ^2.5` · `intl ^0.20` · `audioplayers ^6.8`. Cấu trúc
`lib/core`, `lib/models`, `lib/features/<feature>/`. **Không** FlutterFire — app chỉ gọi REST.

- Riverpod 3: chỉ `Provider`, `FutureProvider`, `Notifier`/`AsyncNotifier`. Không
  `StateProvider`/`StateNotifierProvider`/`ChangeNotifierProvider`. Sau mutation `ref.invalidate(...)`.
- Model: `fromJson` viết tay, không `freezed`/`json_serializable`.
- `--dart-define`: `API_BASE_URL`, `USE_MOCK` (fixture `assets/fixtures/`, copy bằng
  `tool/sync_fixtures.sh`), `DEMO` (nút "Dùng file demo" — không gắn `kDebugMode`).
- `TaxBridgeApi` interface; `DioTaxBridgeApi` và `FakeTaxBridgeApi` (state in-memory tối thiểu).
- Session trong `shared_preferences`; interceptor gắn `X-Session-Token`; `401` → clear → `/login`.
- Home: hàng ngày `‹ Thứ Sáu, 11/09/2026 › [Hôm nay]` (`selectedDateProvider`, Phase 2) + 4 stat
  card + dòng **Tiền vào ngân hàng** + dòng **Thuế khoán ước tính** (`revenue × 1,5%`, tính ở
  client) + badge `draftCount` (Giao dịch) / `unmatchedMoneyCount` (Tiền vào) / tồn đọng (Tồn đọng)
  + nút Báo cáo, Đối soát lịch sử CK. Sau confirm/match/classify: set `selectedDate` = ngày bản
  ghi, mốc `prevDashboard` của ngày đó, invalidate rồi `context.go('/home')`; Home hiện delta
  banner 4 s (`Tiền vào +380.000đ · Doanh thu không đổi ✓`) và tự refresh mỗi 8 s.
  Card/detail có chip nguồn 💬 Zalo / 🎤 Voice / 📷 Ảnh từ `source` + `captureType`.
  Event/Movement Detail có khối **Bằng chứng** ngay dưới hàng chip (`EvidenceBlock`: câu gốc /
  transcript + `Nghe lại` / ảnh chạm phóng to; `asset://demo/*` cho mock).
  Nhãn nút / ô nhập / chip theo bảng `Handles` trong `feature-map/`.
- Capture: `image_picker(imageQuality: 70, maxWidth: 1600)`; `record` `aacLc` → `.m4a`,
  auto-stop 60 s; multipart đúng hai field `type` + `file`.
- `GET /api/health` lúc app start để warm function. Lỗi: một SnackBar chung.

## 8. Môi trường thật và bẫy

- Firebase project **`hackathon-42790`**, region **`asia-southeast1`**, Blaze.
- **URL Functions**: function `api` nhận path **sau** tên function. Prod
  `API_BASE_URL = https://asia-southeast1-hackathon-42790.cloudfunctions.net/api` (app tự
  nối `/api/...` → trên wire là `/api/api/health`, Flask vẫn thấy `/api/health` như local).
  Zalo webhook prod = `<base>/api/zalo/webhook`.
- **Không chạy `firebase init`** (ghi đè `main.py`, `requirements.txt`, rules).
- **Không tạo `functions/.env`** (CLI nạp lên prod). Dùng `.env` ở repo root hoặc
  `functions/.env.local` (gitignored). Firebase chỉ upload `functions/`.
- Bucket là `{project}.firebasestorage.app`; để trống cho `firebase-admin` tự resolve.
- Secrets: `firebase functions:secrets:set <NAME>` **và** `secrets=[...]` trong decorator
  (thiếu → `os.environ` rỗng, không có lỗi để lần); secret chưa tồn tại → deploy fail toàn bộ.
- Cold start ~17 s (import `openai` + `imageio_ffmpeg`), warm ~1 s. Ngày demo:
  `MIN_INSTANCES=1` (tính tiền 24/7, tắt sau demo) + app ping `/api/health`.

## 9. Demo use case bắt buộc (bản duy nhất; số phải đúng)

| UC | Hành động | Kỳ vọng trên Home |
|---|---|---|
| 1 | Register (+ chọn Zalo user optional) | vào Home, có token |
| 2 | Text "bán 3 hộp collagen 450 nghìn chuyển khoản" | SALE DRAFT, BANK/UNPAID → confirm → revenue +450k, receivable +450k |
| 3 | Voice cùng nội dung | như UC2 |
| 4 | Ảnh chuyển khoản 450k "LAN 3HOP" | bankIn +450k, candidate = sale 450k → match → collected +450k, receivable −450k |
| 5 | Ảnh chuyển khoản 380k "COC MINH" | bankIn +380k, badge Tiền vào +1 → Đặt cọc → badge −1, **revenue không đổi** |
| 6 | Ảnh phiếu mua bao bì 220k tiền mặt | PURCHASE DRAFT → confirm → expense +220k |
| 7 | Đóng ngày | daily record + warning; xử lý warning sau → RESOLVED, summary cập nhật |
| 8 | Zalo user chưa link nhắn bot | lưu Firestore, xuất hiện trong dropdown Register |
| 9 | Zalo user đã link nhắn text/ảnh/voice | draft/movement mới hiện sau refresh |

Phase 2 (`requirements-phase2.md` §3, kịch bản ở `feature-map/`):

| UC | Hành động | Kỳ vọng |
|---|---|---|
| 10 | Ảnh CK 380k in `11/09/2026 11:02` | movement `occurredAt` 11/09; app về Home **11/09**, banner hero; `daily_records/2026-09-11` có warning mới |
| 11 | Zalo user nhắn text / ảnh; user chưa link nhắn | bot trả lời `✅ Đã ghi nháp …` / `🏦 Tiền vào …` / hướng dẫn liên kết |
| 12 | Báo cáo **7 ngày** | `summary.revenue` = Σ `byDay`; dòng 11/09 = `dashboard(11/09)` |
| 13 | Home hôm nay có nháp 11/09; register với zaloId có message cũ | card `⚠ Còn …` → Tồn đọng → confirm; SnackBar `Đã xử lý n tin nhắn Zalo cũ` |
| 14 | Ảnh `bank_history.jpg` sau UC4/UC5 | `resultIds` 3, `skippedCount` 2 → Đối soát: Ghép 1, phân loại 2; gửi lại → `resultIds: []` |

## 10. Quy trình

1. Đọc mục liên quan trong plan (grep `## N.`); xác định phase.
2. Thêm/đổi field hay endpoint → sửa `contract/` + cả hai plan trước, code sau.
3. Phong cách PoC: hàm ngắn, ít abstraction, không thêm thư viện ngoài plan. Không thêm
   test/CI/lint ngoài `smoke.sh` trừ khi được yêu cầu.
4. Comment, docstring, message cho user: **tiếng Việt**; identifier: English.
5. Xong việc → tick checkbox phase; plan sai thực tế → sửa plan, ghi lý do trong commit.
6. Feature có kịch bản trong `feature-map/` → chạy kịch bản đó sau khi code (API: `curl`;
   app: iOS Simulator với `DEMO=true`); lệch thì sửa code hoặc sửa feature-map, không để lệch.
   Phase 2: mỗi UC10–14 có đúng một file feature-map.
7. Không tự ý deploy Functions, đổi `MIN_INSTANCES`, set secret, push git; hỏi trước.

## 11. Git

- Không commit `.env`, `.env.local`, service account JSON, `functions/venv/`. App commit `pubspec.lock`.
- Message `feat|fix|docs|chore: <mô tả ngắn>`; commit/push chỉ khi được yêu cầu.
