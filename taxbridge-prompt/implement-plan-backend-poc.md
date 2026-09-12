# TaxBridge — Implementation Plan Backend (PoC)

_Python 3.12 · Flask · Firebase Functions gen2 · Firestore · Cloud Storage · OpenAI_

Mục tiêu: backend chạy end-to-end 9 UC ở `CLAUDE.md` §9. Contract (DTO/enum/endpoint/
status code/fixtures) ở `contract/`, không lặp lại ở đây. Phạm vi làm / không làm ở
`CLAUDE.md` §4.

## 1. Repo structure

```text
taxbridge-server/
├── firebase.json
├── .env                    # dev local (gitignored): OPENAI_API_KEY, GCLOUD_PROJECT, ZALO_*
├── functions/
│   ├── main.py             # Functions wrapper (mục 10)
│   ├── requirements.txt
│   └── app/
│       ├── flask_app.py    # create_app(): initialize_app guard, load_dotenv, before_request, blueprint
│       ├── config.py       # model id, reasoning effort, giới hạn file
│       ├── firestore.py    # db, new_id(), now_iso()
│       ├── storage.py      # upload bytes → download URL có token (mục 4.2)
│       ├── openai_client.py           # extract_event / extract_transfer / extract_image / transcribe
│       ├── errors.py       # ApiError(status, code, message) → `{code, message}`; leaf, mọi module import được
│       ├── auth_service.py
│       ├── capture_service.py         # process_capture() dùng chung app + Zalo
│       ├── event_service.py           # update / confirm / reject
│       ├── reconciliation_service.py  # candidates / match / classify
│       ├── dashboard_service.py       # dashboard + close day + resolve_warnings
│       ├── zalo_service.py            # normalize, download media, aac_to_m4a
│       ├── openapi.yaml   # spec viết tay theo contract/; serve ở /api/openapi.yaml
│       └── routes/
│           auth.py  captures.py  events.py  dashboard.py  reconciliation.py  close_day.py
│           zalo.py  docs.py   # docs.py: Swagger UI (/api/docs) + spec, Swagger UI lấy từ CDN
├── tests/smoke/smoke.sh    # 9 UC bằng curl + Zalo simulator (contract/endpoints.md)
└── tests/seed_demo.py      # account demo + 3 daily record cũ cho prod (Phase 6)
```

## 2. Firestore schema

Thời gian lưu **string ISO `+07:00`** (không dùng Firestore `Timestamp`): DTO trả thẳng, lọc theo ngày
= so 10 ký tự đầu, sort = so chuỗi. Enum theo `contract/README` §4.

| Collection | Field |
|---|---|
| `accounts/{accountId}` | `accountId, username, passwordHash, businessId, zaloId?, createdAt` |
| `businesses/{businessId}` | `businessId, name, ownerAccountId, createdAt` |
| `sessions/{token}` | `token, accountId, businessId, createdAt, lastUsedAt` — doc id = token thô, không expiry |
| `zalo_users/{zaloId}` | `zaloId, displayName, linkedAccountId?, linkedBusinessId?, firstSeenAt, lastSeenAt` |
| `zalo_unlinked_messages/{messageId}` | shape `contract/fixtures/zalo/normalized_*.json` + `receivedAt` |
| `businesses/{b}/captures/{captureId}` | `captureId, source: APP\|ZALO, type, text?, transcript?, fileUrl?, zaloMessageId?, status, resultType?, resultId?, error?, createdAt` |
| `businesses/{b}/events/{eventId}` | DTO `BusinessEvent` (gồm `source, captureType, evidenceText, evidenceUrl`) + `sourceCaptureId, createdAt, updatedAt` |
| `businesses/{b}/money_movements/{movementId}` | DTO `MoneyMovement` trừ `candidates` (gồm `source, captureType, evidenceText, evidenceUrl`) + `sourceCaptureId, classifiedAt?` |
| `businesses/{b}/daily_records/{date}` | **đúng shape DTO `DailyRecord`** (nested `summary`, mảng `warnings`) |

- Mỗi account đúng một business. `zalo_users.linkedAccountId == null` = chưa link.
- `candidates` tính lúc GET movement, không persist.
- `.env` ở repo root có `GCLOUD_PROJECT` → `create_app()` set `projectId` + `storageBucket`; có
  `FIRESTORE_EMULATOR_HOST` → dùng credential emulator, không cần ADC (`tests/smoke/emulator.sh`).

## 3. Auth

**Register** `POST /api/register` `{username, password, zaloId?}` → `201 Session`:

1. username tồn tại → `409 USERNAME_TAKEN`; `zaloId` không tồn tại → `404`; đã link → `409 ZALO_USER_LINKED`.
2. Tạo `accounts` (`passwordHash = generate_password_hash(password)`), `businesses`
   (`name = "Hộ kinh doanh của {username}"`).
3. Có `zaloId` → update `zalo_users` `linkedAccountId` / `linkedBusinessId`.
4. Tạo `sessions/{token}` (`"tb_" + secrets.token_urlsafe(32)`), trả `Session`.

**Login** `POST /api/login` → `200 Session`: query `accounts` theo `username`,
`check_password_hash`; sai → `401`. Mỗi login tạo session mới, không thu hồi cũ.

**Logout** `POST /api/logout` → xóa `sessions/{token}` → `204`.

**Resolve session** — `before_request` trong `create_app()`:

```python
PUBLIC = {"/api/health", "/api/register", "/api/login",
          "/api/zalo-users/unlinked", "/api/zalo/webhook"}

@app.before_request
def load_session():
    if request.path in PUBLIC:
        return None
    token = (request.headers.get("X-Session-Token")                       # prod: Cloud Run chặn Bearer lạ
             or request.headers.get("Authorization", "").removeprefix("Bearer ")).strip()
    doc = db.collection("sessions").document(token).get() if token else None
    if not doc or not doc.exists:
        return {"code": "UNAUTHORIZED", "message": "Token không hợp lệ."}, 401
    g.account_id, g.business_id = doc.get("accountId"), doc.get("businessId")
```

Trên Functions, Flask vẫn thấy `request.path = /api/...` (xem `CLAUDE.md` §8), nên
`PUBLIC` dùng được cả local lẫn prod.

## 4. Capture pipeline

`POST /api/captures` — JSON `{type: TEXT, text}` hoặc multipart `type` + `file`
(JPEG/PNG/M4A ≤ 10 MB, audio ≤ 60 s; sai → `413`/`415`). Trả `CaptureResult`.

```text
process_capture(business_id, source, type, text=None, file_bytes=None, zalo_message_id=None)
1. Tạo captures/{id} status=PROCESSING (file → storage.upload (mục 4.2), lưu fileUrl = download URL;
   voice Zalo upload bản .m4a sau remux để app phát được).
2. Theo type:
   TEXT           → extract_event(text)
   AUDIO          → transcribe(m4a) → extract_event(transcript)
   IMAGE_RECEIPT  → extract_event(image)
   IMAGE_TRANSFER → extract_transfer(image)
   IMAGE_UNKNOWN  → extract_image(image) → kind RECEIPT/TRANSFER/OTHER → nhánh tương ứng
3. Event → events/{id} DRAFT (resultType=EVENT); transfer → money_movements/{id} UNMATCHED
   (resultType=MONEY_MOVEMENT); OTHER → FAILED error=UNRECOGNIZED_IMAGE.
   `occurredAt`: **Phase 2 ②** (mục 12) — ảnh lấy ngày in trên chứng từ, text/voice chỉ khi nói
   rõ, còn lại = now() (`Asia/Ho_Chi_Minh`). (v1 luôn now().)
   Ghi thêm `source` (APP|ZALO) và `captureType` lên event/movement — copy từ capture;
   `IMAGE_UNKNOWN` ghi type sau khi đã biết `kind` (IMAGE_RECEIPT | IMAGE_TRANSFER).
   App dùng 2 field này để hiện chip nguồn (plan FE §6).
   Bằng chứng (contract §5.1): evidenceText = text (TEXT) | transcript (AUDIO) | null;
   evidenceUrl = fileUrl (AUDIO / IMAGE_*) | null. Transcript cũng ghi captures.transcript.
4. Update capture DONE/FAILED; trả CaptureResult.
   Exception từ AI → FAILED + error=AI_EXTRACTION_FAILED, HTTP 200.
   AI trả `type=UNKNOWN` và `amount=0` (text chào hỏi, ảnh nhãn sản phẩm — eval A4/R3) → FAILED,
   error=NO_TRANSACTION (text/audio) | UNRECOGNIZED_IMAGE (ảnh); không tạo draft rác.
```

### 4.1 OpenAI

`config.py`: `VISION_MODEL = "gpt-5.6-terra"`, `REASONING_EFFORT = "low"`,
`TRANSCRIBE_MODEL = "gpt-transcribe"`. Fallback: vision chậm trên sân → `gpt-5.6-luna`
(cùng API); audio → `gpt-4o-transcribe` + `language="vi"`.

Structured Outputs qua Responses API + Pydantic (mọi field bắt buộc, nullable dùng `Optional`).
Model chính lỗi (exception) → thử lại một lần với model fallback rồi mới ném lỗi:

```python
class EventExtraction(BaseModel):
    type: Literal["SALE", "PURCHASE", "DEPOSIT", "OWNER_MONEY", "UNKNOWN"]
    amount: int                       # VND
    description: str
    counterparty: Optional[str]
    paymentMethod: Literal["CASH", "BANK", "UNKNOWN"]
    paymentStatus: Literal["UNPAID", "PAID", "UNKNOWN"]
    confidence: float
    occurredDate: Optional[str]      # Phase 2 ②, như TransferExtraction

class TransferExtraction(BaseModel):
    direction: Literal["IN", "OUT"]
    amount: int
    counterparty: Optional[str]
    memo: Optional[str]
    occurredDate: Optional[str]      # Phase 2 ②: "YYYY-MM-DD" | "YYYY-MM-DDTHH:MM" in trên chứng từ, null nếu không có
    # v1 cố ý không đọc ngày (ảnh demo in 11/09 → rơi khỏi dashboard hôm nay). Phase 2 đổi:
    # app về Home của ngày bản ghi (plan FE §10) nên hero vẫn giữ; xem requirements-phase2.md ②.

class ImageExtraction(BaseModel):     # IMAGE_UNKNOWN (ảnh Zalo)
    kind: Literal["RECEIPT", "TRANSFER", "OTHER"]
    event: Optional[EventExtraction]
    transfer: Optional[TransferExtraction]

resp = client.responses.parse(
    model=VISION_MODEL, reasoning={"effort": REASONING_EFFORT},
    input=[{"role": "system", "content": SYSTEM_PROMPT},
           {"role": "user", "content": [
               {"type": "input_text", "text": text_or_instruction},
               {"type": "input_image", "image_url": f"data:image/jpeg;base64,{b64}"}]}],  # bỏ khi TEXT
    text_format=EventExtraction)
out = resp.output_parsed
```

Rule trong system prompt (tiếng Việt, ngắn). Dòng đánh dấu *(eval …)* là lỗi lặp trong lần
chạy `test-data/` trên backend cũ 11/09 (11/21 pass,
`test-data/runs/2026-09-11-old-backend/report.md`) — prompt mới phải qua được các case đó:

- Bối cảnh hộ kinh doanh VN, người nói là chủ hộ. "bán / khách" → SALE; "mua / nhập /
  phiếu thu của cửa hàng khác" → PURCHASE; "cọc" → DEPOSIT; "rút / góp / tiền nhà / bỏ vào
  quỹ" → OWNER_MONEY *(eval T4)*.
- Số: "450 nghìn" = 450000, "1 triệu 2" = 1200000, "1 triệu 250" = 1250000 *(eval T6)*,
  "300k" = 300000, "1tr5" = 1500000. Người nói tự sửa giữa chừng ("300 nghìn à không, 320")
  → lấy số chốt cuối *(eval A3)*.
- SALE + "chuyển khoản / ck / banking" → `BANK` + `UNPAID`; chỉ `PAID` khi nói rõ "đã nhận /
  đã thanh toán" hoặc tiền mặt. Không nói hình thức thanh toán → `paymentMethod=UNKNOWN`
  và `paymentStatus=UNKNOWN`, không đoán *(eval T2)*. PURCHASE có phiếu/hóa đơn → `PAID`.
- Hóa đơn: chủ hộ chụp hóa đơn do cửa hàng khác phát hành → chủ hộ là người mua → `PURCHASE`,
  `counterparty` = cửa hàng phát hành (không lấy tên khách trên phiếu — receipt.jpg từng bị đọc
  thành SALE/"Anh Tuấn"). `amount` = "Tổng cộng / Thành tiền"; không lấy "Tiền khách đưa" /
  "Tiền thối" *(eval R2)*.
- Ảnh chuyển khoản — đọc theo góc nhìn **chủ shop**, không phải góc nhìn người chụp màn hình:
  - `direction=IN` là **mặc định**; màn hình "Chuyển khoản thành công" khách chụp gửi cho shop
    vẫn là tiền VÀO shop. `OUT` chỉ khi rõ chính chủ shop trả tiền đi *(eval M1/M6 — đo 12/09:
    không có câu này thì model trả `OUT` cho cả `transfer_match` lẫn `transfer_deposit`,
    `bankIn` = 0 và hero chết)*.
  - `counterparty` = **người gửi** ("Từ / Nguồn tiền"). Tên ở dòng "Đến / Người nhận /
    Người thụ hưởng" là chủ shop — không bao giờ lấy làm `counterparty` *(eval M1/M6 — đo 12/09:
    model từng trả `MAI ANH TUAN` = chủ shop)*. Ảnh không hiện tên người gửi → lấy tên từ nội dung
    CK ("LAN 3HOP" → "LAN"); nội dung không có tên người → `null`.
  - Ngày: **Phase 2 ②** đọc ngày (+ giờ) in trên ảnh → `occurredDate`; text/voice chỉ khi nói rõ
    (prompt nhận `Hôm nay là YYYY-MM-DD` để quy đổi "hôm qua"); không có → `null` (mục 12).
- Không chắc → `UNKNOWN`, `confidence` thấp; không bịa số, không biến số lượng / mã vạch /
  giờ thành số tiền *(eval A4/R3)*.

Audio → `extract_event(transcript)`. Zalo `.aac` remux trước (snippet `contract/README` §6).

```python
TRANSCRIBE_PROMPT = ("Chủ hộ kinh doanh Việt Nam đọc một giao dịch bán/mua hàng: "
                     "tên khách, số lượng, số tiền (nghìn/triệu/k), cách thanh toán.")
TRANSCRIBE_KEYWORDS = ["chuyển khoản", "tiền mặt", "đặt cọc", "nghìn", "triệu", "hộp", "collagen"]

def transcribe(m4a: bytes) -> str:
    kw = dict(model=TRANSCRIBE_MODEL, file=("voice.m4a", m4a), prompt=TRANSCRIBE_PROMPT)
    if TRANSCRIBE_MODEL == "gpt-transcribe":
        # extra_body: `languages`/`keywords` chạy được trên mọi version SDK (requirements
        # không pin cứng). SDK 3.13 đã có sẵn hai param này — gửi thẳng cũng được.
        kw["extra_body"] = {"languages": ["vi"], "keywords": TRANSCRIBE_KEYWORDS}
    else:
        kw["language"] = "vi"
    return client.audio.transcriptions.create(**kw).text
```

`gpt-transcribe` chỉ nhận `languages` (số nhiều) — gửi `language` sẽ lỗi; nhận `m4a`,
không nhận `aac`.

### 4.2 Storage — download URL có token

Không dùng signed URL (Functions cần quyền ký blob). Cách đã chạy với `smoke-media/*`:

```python
import logging, uuid
from urllib.parse import quote
from firebase_admin import storage

def upload(path: str, data: bytes, content_type: str) -> str | None:
    try:
        bucket = storage.bucket(); blob = bucket.blob(path)
        token = uuid.uuid4().hex
        blob.metadata = {"firebaseStorageDownloadTokens": token}
        blob.upload_from_string(data, content_type=content_type)
        return (f"https://firebasestorage.googleapis.com/v0/b/{bucket.name}"
                f"/o/{quote(path, safe='')}?alt=media&token={token}")
    except Exception as e:                      # emulator local không có Storage
        logging.warning("storage upload lỗi: %s", e); return None
```

`path = f"captures/{business_id}/{capture_id}.{ext}"` (`jpg` | `png` | `m4a`); `content_type`
đúng (`image/jpeg`, `image/png`, `audio/mp4`) để `Image.network` / `audioplayers` mở được.
URL public với ai có link — chấp nhận PoC (contract §5.1).

## 5. Event: update / confirm / reject

- `PUT /api/events/{id}`: chỉ khi `DRAFT` (`409 INVALID_STATE`), chỉ 7 field ở
  `contract/endpoints.md`, field lạ → `400`.
- `confirm` / `reject`: `DRAFT` → `CONFIRMED` / `REJECTED`, cập nhật `updatedAt`, rồi
  `resolve_warnings(business_id, event_id)` (mục 8). Trả `BusinessEvent`.

## 6. Money movement: candidates / match / classify

Candidates (tính lúc `GET /api/money-movements/{id}` và trong list, chỉ khi `UNMATCHED`):
event `SALE + CONFIRMED + UNPAID` của business, `score > 0`, tối đa 3, giảm dần:

```python
score = 0
if movement.amount == event.amount:                 score += 0.6
if similar(movement.memo or movement.counterparty,
           event.counterparty or event.description): score += 0.3   # token không dấu, lower-case
if same_day(movement.occurredAt, event.occurredAt): score += 0.1
```

Chỉ giữ candidate `score >= 0.3` (`config.CANDIDATE_MIN_SCORE`): riêng "cùng ngày" 0.1 không đủ —
nếu không thì UC5 (380k) sẽ gợi ý ghép với sale 450k của UC3, hỏng hero "không có candidate".

- `match {eventId}`: movement `UNMATCHED` → `MATCHED`, `matchedEventId`; event
  `paymentStatus = PAID`. Trả `MoneyMovement` (`candidates: []`).
- `classify {type}`: `UNMATCHED` → `CLASSIFIED`, `classificationType`, `classifiedAt`.
  **Không tạo event, không đổi revenue** (hero). Trả `MoneyMovement`.
- Sai trạng thái → `409 INVALID_STATE`. Sau cả hai: `resolve_warnings(business_id, movement_id)`.

## 7. Dashboard

`GET /api/dashboard?date=YYYY-MM-DD` (mặc định hôm nay `Asia/Ho_Chi_Minh`). Lọc theo
`occurredAt` trong ngày, tính trong Python:

```text
revenue             = Σ amount  events  SALE     CONFIRMED
expense             = Σ amount  events  PURCHASE CONFIRMED
collected           = Σ amount  events  SALE     CONFIRMED  paymentStatus=PAID
receivable          = revenue − collected
bankIn              = Σ amount  money_movements direction=IN   (mọi status)
draftCount          = count events status=DRAFT
unmatchedMoneyCount = count money_movements status=UNMATCHED
```

## 8. Close day & daily records

`POST /api/close-day {date}` → tính summary + warning tại thời điểm gọi, **upsert**
`daily_records/{date}` đúng shape DTO, trả `DailyRecord`. Gọi lại cùng ngày: cập nhật
record, warning đã `RESOLVED` giữ nguyên, warning mới thêm vào.

Warning: mỗi event `DRAFT` → `DRAFT_EVENT:{eventId}`; mỗi movement `UNMATCHED` →
`UNMATCHED_MONEY:{movementId}`; `warningCount` = số `OPEN`.

`resolve_warnings(business_id, resource_id)` — gọi sau confirm/reject/match/classify:
đọc mọi `daily_records` của business; warning `OPEN` có `resourceId == resource_id` →
`RESOLVED` + `resolvedAt`; recompute `summary` + `warningCount` của record đó; ghi lại.

`GET /api/daily-records` (sort `date` giảm dần trong Python) · `GET /api/daily-records/{date}`.

## 9. Zalo webhook

Payload thật, field, media URL, remux, probe body rỗng, secret header — `contract/README` §6.

```text
POST /api/zalo/webhook
1. Header X-Bot-Api-Secret-Token != ZALO_WEBHOOK_SECRET → 401.
2. Body rỗng / không có message / không có message.from.id → 200 {"ok": true}.
3. Normalize → shape zalo/normalized_*.json; upsert zalo_users/{zaloId} (displayName, lastSeenAt).
   messageType suy từ field có mặt: voice_url→AUDIO, photo_url→IMAGE, sticker→STICKER,
   text→TEXT, còn lại→OTHER. Sticker/loại lạ VẪN normalize + upsert user (nếu bỏ qua thì
   user nhắn sticker trước sẽ không hiện ở dropdown Register — UC8 hỏng).
4. linkedBusinessId == null → lưu zalo_unlinked_messages/{messageId} → 200 (mọi messageType).
5. Đã link → text: process_capture(TEXT)
             photo_url: GET bytes → process_capture(IMAGE_UNKNOWN)
             voice_url: GET bytes → aac_to_m4a → process_capture(AUDIO)
             STICKER | OTHER: không gọi AI, không tạo capture (không có giao dịch để trích).
   source=ZALO, zaloMessageId=messageId.
6. Luôn 200 {"ok": true}, kể cả AI lỗi (đã ghi capture.error).
```

`GET /api/zalo-users/unlinked` → `zalo_users` có `linkedAccountId == null`, sort
`lastSeenAt` giảm dần. Không xử lý lại message cũ sau khi link (UC9 gửi message mới).

## 10. Functions wrapper & requirements

`functions/main.py`:

```python
import os
from firebase_functions import https_fn, options
from app.flask_app import create_app

app = create_app()   # create_app() gọi firebase_admin.initialize_app() có guard

@https_fn.on_request(
    region="asia-southeast1", timeout_sec=120, memory=options.MemoryOption.MB_512,
    min_instances=int(os.environ.get("MIN_INSTANCES", "0")),
    # ZALO_BOT_TOKEN không có ở đây: PoC không gọi sendMessage nên không code nào đọc, mà
    # deploy 12/09 fail vì account thiếu `secretmanager.secrets.setIamPolicy` để cấp quyền
    # đọc secret mới tạo cho service account. Cần bot reply → thêm lại + nhờ admin chạy
    # `gcloud secrets add-iam-policy-binding ZALO_BOT_TOKEN --member serviceAccount:
    # 495996584842-compute@developer.gserviceaccount.com --role roles/secretmanager.secretAccessor`.
    secrets=[options.SecretParam(n) for n in ("OPENAI_API_KEY", "ZALO_WEBHOOK_SECRET")])
def api(req: https_fn.Request) -> https_fn.Response:
    with app.request_context(req.environ):
        return app.full_dispatch_request()
```

`functions/requirements.txt`: `firebase-functions firebase-admin flask openai pydantic
python-dotenv requests imageio-ffmpeg`. Không thêm thư viện khác.

## 11. Phases (theo time-box build day, `hackathon-prep-checklist.md` §4)

### Phase 0 — Tối 11/09: skeleton

- [x] `main.py`, `create_app()` + guard `initialize_app` + `load_dotenv`, `config.py`,
      `firestore.py`, `storage.py`, `/api/health`.
- [x] `before_request` resolve session (mục 3). (Không cần seed tay: register có ngay.)
- [x] `openai_client.py` với 3 schema + `transcribe`.
- [x] Chạy thử 4 asset demo với AI thật, đối chiếu số với mục 9 CLAUDE.md (12/09: đúng hết
      450k / 450k / 380k / 220k; đã sửa prompt `direction` + `counterparty` ảnh CK, mục 4.1).
- [x] `requirements.txt`, `.env`, secrets `ZALO_*` (đã có trên Secret Manager).
- [x] **Deploy thử 1 lần** (11/09 tối) → URL thật; `smoke.sh` 9 UC PASS trên prod kể cả multipart,
      Zalo ảnh/voice (media = Storage download URL `smoke-media/*`), remux ffmpeg. Capture 2–9 s.
      Bẫy đã dính: Cloud Run chặn `Authorization: Bearer` lạ → đổi sang `X-Session-Token` (contract §2).
- [x] `tests/smoke/smoke.sh` (9 UC, PASS trên emulator 11/09 tối; ảnh/voice Zalo cần `ZALO_MEDIA`)
      + `tests/smoke/emulator.sh` (Firestore emulator + Flask, không cần ADC).

### Phase 1 — 09:30 Tracer bullet

- [x] `POST /api/captures` TEXT → `process_capture` → `events` DRAFT.
- [x] `GET /api/events/{id}`, `confirm`.

### Phase 2 — 10:15 Auth + events + dashboard

- [x] `register` / `login` / `logout`, `GET /api/zalo-users/unlinked`.
- [x] `GET /api/events?status=`, `PUT`, `reject`.
- [x] `GET /api/dashboard` 7 field.

### Phase 3 — 11:30 Ảnh + tiền vào

- [x] Multipart → Storage; `IMAGE_RECEIPT` → event; `IMAGE_TRANSFER` → movement.
- [x] `storage.upload` trả download URL có token (mục 4.2); `evidenceText`/`evidenceUrl` trên
      event/movement (mục 4 bước 3); `smoke.sh` UC2/UC4 assert có key, trên prod thêm
      `curl -sI $evidenceUrl` → 200.
- [x] `GET /api/money-movements[?status]`, `/{id}` + candidates, `match`, `classify`.

### Phase 4 — 12:30 Voice

- [x] `AUDIO` → transcribe → extract.

### Phase 5 — 13:00 Close day + Zalo

- [x] `close-day` upsert, `daily-records` list/detail, `resolve_warnings` sau mọi mutation.
- [x] Zalo webhook (mục 9): secret, probe, normalize, unlinked, linked text/image/voice, remux.
- [x] `IMAGE_UNKNOWN` → `kind`.
- [x] `source` + `captureType` trên event/movement (mục 2, 4 bước 3); `smoke.sh` UC9 assert
      `source == "ZALO"` trên draft/movement tạo từ webhook.

### Phase 6 — 14:00 Deploy & freeze

- [x] Deploy Functions, `MIN_INSTANCES=1`, trỏ Zalo webhook sang prod, seed prod
      (12/09: webhook đã trỏ sẵn `<base>/api/zalo/webhook`, set lại kèm `secret_token`,
      Zalo trả `webhook.ok`; seed `tuan/123456` + 3 daily record 09–11/09 bằng
      `tests/seed_demo.py`, warning rỗng để không có nút Xử lý trỏ vào resource ma).
- [x] `smoke.sh` chạy đủ 9 UC trên URL thật (12/09: **86 pass · 0 fail**, có
      `evidenceUrl` Storage trả 200). **14:30 feature freeze.**

---

# Phase 2 — bổ sung 12/09 (`requirements-phase2.md`)

Thứ tự: 12 → 16 → 13 → 14 → 15. Mỗi mục ghi đúng file bị đụng; không thêm module mới ngoài
`report_service.py` và `bank_history` trong `capture_service.py`.

## 12. Ngày trên chứng từ (②) — `capture_service`, `openai_client`, `dashboard_service`, `event_service`

Schema: `EventExtraction.occurredDate`, `TransferExtraction.occurredDate` (mục 4.1). Prompt:
bỏ dòng "KHÔNG đọc ngày giờ"; thêm

```text
Ngày giao dịch (occurredDate):
- Ảnh: lấy ngày (và giờ nếu có) IN TRÊN chứng từ, đổi "11/09/2026 11:02" → "2026-09-11T11:02".
- Câu nói / text: chỉ khi nêu rõ ("hôm qua", "sáng 10/9", "tuần trước thứ hai"); quy đổi theo
  "Hôm nay là {today}". Không nêu → null. Không đoán.
```

`instruction` của `extract_event(text=…)` thêm dòng `Hôm nay là {today()}.`

```python
def resolve_occurred_at(raw: str | None) -> str:
    """Ngày AI đọc được → ISO +07:00; không hợp lệ / ngoài [now-365d, now+1d] → now_iso()."""
    if not raw:
        return now_iso()
    try:
        dt = datetime.fromisoformat(raw)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=TZ)
        if len(raw) == 10:                                  # chỉ ngày → 12:00
            dt = dt.replace(hour=12, minute=0, second=0)
    except ValueError:
        return now_iso()
    if not (now() - timedelta(days=365) <= dt <= now() + timedelta(days=1)):
        return now_iso()
    return dt.isoformat(timespec="seconds")
```

`process_capture` bước 3: `ts = resolve_occurred_at(extraction.occurredDate)`; `createdAt`/`updatedAt`
vẫn `now_iso()`. `CaptureResult` thêm `occurredAt` (= `ts`; `None` khi FAILED), `resultIds: []`,
`skippedCount: 0` (mục 15 dùng). Sau khi ghi event/movement → `sync_record(business_id, date_of(ts))`.

`dashboard_service.sync_record(business_id, date)` thay `resolve_warnings`:

```text
record = daily_records/{date}; không tồn tại → return (ngày chưa đóng, không tạo).
events, movements của ngày → warnings mới cho DRAFT / UNMATCHED (setdefault như close_day);
warning OPEN mà resource không còn DRAFT / UNMATCHED (hoặc bị xóa) → RESOLVED + resolvedAt;
summary, warningCount, updatedAt → set lại.
```

`close_day` = tạo record nếu chưa có rồi gọi `sync_record`. `confirm/reject/match/classify` gọi
`sync_record(business_id, date_of(resource.occurredAt))` thay vì quét mọi record. `event_service.update`
đổi `occurredAt` → validate ISO, sync **cả ngày cũ và mới**. `seed_demo.py` không đổi.

Smoke UC10 (`contract/endpoints.md`): ảnh `transfer_deposit.jpg` → `occurredAt` bắt đầu
`2026-09-11`; `daily-records/2026-09-11` (seed) có warning mới; classify → RESOLVED.

## 13. Báo cáo theo khoảng (④) — `report_service.py`, `routes/reports.py`

`GET /api/reports?from&to` → DTO `contract/fixtures/report.json`.

```python
def report(business_id, from_, to):
    from_, to = check_date(from_), check_date(to)
    if to < from_ or (date.fromisoformat(to) - date.fromisoformat(from_)).days >= 92:
        raise errors.validation("Khoảng tối đa 92 ngày, to >= from.")
    events = [e for e in all events if from_ <= date_of(e["occurredAt"]) <= to]
    movements = ... cùng lọc
    summary = _summary(events) + bankIn + saleCount/purchaseCount (CONFIRMED) + draftCount + unmatchedMoneyCount
    byDay: group theo date_of, chỉ ngày có dữ liệu, sort desc; mỗi dòng revenue/expense/collected/bankIn/saleCount/draftCount/unmatchedMoneyCount
    byType: CONFIRMED gộp theo type, bỏ type count=0
    return {"from": from_, "to": to, "days": (to-from_).days+1, "summary", "byDay", "byType"}
```

Dùng lại `dashboard_service._summary` (đổi thành public `summary()`). Không index Firestore:
đọc cả collection rồi lọc (PoC, vài trăm doc).

## 14. Tồn đọng + replay Zalo (③) — `dashboard_service`, `routes/pending.py`, `zalo_service`, `routes/zalo.py`

`dashboard()` thêm `pastDraftCount` / `pastUnmatchedCount`: đếm DRAFT / UNMATCHED có
`date_of(occurredAt) < date` (đọc cả collection một lần, tách 2 nhóm; tránh đọc 2 lần).

`GET /api/pending` → `pending.json`: `draftEvents` = `to_dto` mọi DRAFT sort `occurredAt` **tăng**;
`unmatchedMovements` = `list_movements(status="UNMATCHED")` đảo chiều sort (kèm candidates);
`byDate` = đếm theo ngày, sort tăng.

`POST /api/zalo-users/<zalo_id>/replay` (auth):

```text
1. zalo_users/{zalo_id}.linkedAccountId != g.account_id → 404.
2. zalo_unlinked_messages where zaloId == zalo_id (đọc rồi lọc Python), sort sentAt tăng.
3. Mỗi message chưa có replayedAt:
   TEXT / IMAGE / AUDIO → process_capture(...) như handle() (download có thể 4xx → try/except →
   đếm failed); capture.status FAILED cũng đếm failed. STICKER / OTHER → skipped.
   Ghi replayedAt = now_iso() (kể cả failed, không thử lại).
4. Trả {zaloId, replayed, done, failed, skipped}. Không gọi reply() khi replay.
```

Tách `zalo_service._capture_message(business_id, message) -> dict | None` để `handle()` và
`replay()` dùng chung. Register **không** tự replay — app gọi endpoint sau khi có session (plan FE §12).

## 15. Đối soát lịch sử CK (①) — `openai_client`, `capture_service`, `reconciliation_service`

```python
class BankHistoryExtraction(BaseModel):
    transfers: list[TransferExtraction]       # mỗi dòng có occurredDate; dòng thiếu số tiền → bỏ
```

`extract_bank_history(image)` instruction: "Ảnh danh sách giao dịch trong app ngân hàng / sao kê
của CHỦ SHOP. Mỗi dòng = một transfer: amount (int), direction (`+`/"nhận"/"báo có" → IN;
`-`/"chuyển đi"/"thanh toán" → OUT), memo nguyên văn, counterparty nếu có, occurredDate từ cột
ngày. Bỏ dòng số dư / tiêu đề / dòng không có số tiền. Không gộp, không bịa."

`process_capture` nhánh `IMAGE_BANK_HISTORY`:

```text
rows = extract_bank_history(file).transfers; rows rỗng → FAILED UNRECOGNIZED_IMAGE.
existing = all_movements(business_id)
for r in rows (amount > 0):
    ts = resolve_occurred_at(r.occurredDate)
    dup = any(m.direction == r.direction and m.amount == r.amount and date_of(m.occurredAt) == date_of(ts)
              and (similar(m.memo, r.memo) or (not m.memo and not r.memo)) for m in existing)
    dup → skipped += 1; else tạo movement (captureType=IMAGE_BANK_HISTORY, evidenceUrl = ảnh, sourceCaptureId) → ids.append
sync_record cho mỗi ngày có movement mới (set ngày, gọi 1 lần / ngày).
capture: resultType=MONEY_MOVEMENT_BATCH, resultId=None, resultIds=ids, skippedCount=skipped,
occurredAt = max ts của movement mới (None nếu ids rỗng). DONE kể cả ids rỗng.
```

`check_upload`: `IMAGE_BANK_HISTORY` validate như ảnh. `CAPTURE_TYPES` / `UPLOAD_TYPES` thêm.
Dedupe chỉ ở nhánh này; ảnh CK đơn lẻ (`IMAGE_TRANSFER`) không dedupe (giữ v1).

## 16. Zalo bot trả lời (⑤) — `zalo_service`, `main.py`, `config.py`

`main.py`: thêm `"ZALO_BOT_TOKEN"` vào tuple `secrets=[...]` (IAM đã cấp 12/09 12:05 cho
`495996584842-compute@developer.gserviceaccount.com`; xóa comment cũ). Local: `.env` root.

```python
ZALO_BOT_API = "https://bot-api.zapps.me/bot{token}/{method}"     # config.py

def reply(chat_id: str, text: str) -> None:
    """Gửi trong request webhook, trước khi trả 200. Không bao giờ raise."""
    token = os.environ.get("ZALO_BOT_TOKEN", "")
    if not token:
        logging.warning("ZALO_BOT_TOKEN rỗng — bỏ qua reply"); return
    try:
        r = requests.post(ZALO_BOT_API.format(token=token, method="sendMessage"),
                          json={"chat_id": chat_id, "text": text}, timeout=10)
        logging.info("sendMessage → %s %s", r.status_code, r.text[:200])   # ghi shape thật vào contract §6.1
    except Exception as e:
        logging.warning("sendMessage lỗi: %s", e)
```

`reply_text(result: dict | None, business_id, message) -> str | None` theo bảng contract §6.1:
`result is None` (chưa link) → hướng dẫn kèm `displayName`; EVENT → đọc event để lấy loại /
amount / counterparty / thanh toán; MOVEMENT → `get_dto` để biết số candidate; FAILED → câu mẫu;
STICKER/OTHER → `None`. `handle()`: sau khi có `result` → `text = reply_text(...)`; `text` →
`reply(message["chatId"], text)`. Smoke: token rỗng → log "bỏ qua reply" là đủ (UC11); test thật
bằng Zalo trên điện thoại.

## 17. Phases Phase 2 (build day chiều 12/09)

### Phase 7 — ② ngày chứng từ + ⑤ Zalo reply (~45 phút)

- [ ] Mục 12: schema + prompt + `resolve_occurred_at`; `CaptureResult` thêm 3 field; `sync_record`
      thay `resolve_warnings`; `update` đổi ngày sync 2 ngày.
- [ ] Mục 16: `reply` / `reply_text`; `main.py` thêm secret; `.env` local có `ZALO_BOT_TOKEN`.
- [ ] `smoke.sh` UC10 + UC11; chạy lại UC1–9 (số cũ không đổi vì fixture/ảnh cùng ngày 11/09 →
      **dashboard trong smoke đọc `date=2026-09-11` cho UC4–6**, còn text/voice vẫn hôm nay).
- [ ] `openapi.yaml` cập nhật (CaptureResult, prompt không đổi spec).

### Phase 8 — ④ báo cáo + ③ tồn đọng / replay (~40 phút)

- [ ] Mục 13: `report_service` + route; smoke UC12.
- [ ] Mục 14: `dashboard` 2 field; `/api/pending`; `replay`; smoke UC13.
- [ ] `openapi.yaml`: `Report`, `Pending`, `ReplayResult`, `Dashboard`.

### Phase 9 — ① lịch sử CK (~40 phút + ảnh demo 20 phút)

- [ ] `demo-assets/bank_history.jpg` (checklist: 5 dòng, 2 trùng UC4/UC5, 1 OUT, ngày 10–11/09).
- [ ] Mục 15: schema, nhánh capture, dedupe; smoke UC14 (gửi 2 lần).
- [ ] `openapi.yaml`: `IMAGE_BANK_HISTORY`, `MONEY_MOVEMENT_BATCH`.

### Deploy

- [ ] Sau Phase 7: `firebase deploy --only functions:api` (hỏi trước) — lần này có secret
      `ZALO_BOT_TOKEN`; deploy fail → kiểm tra lại IAM binding. Nhắn Zalo thật từ điện thoại → bot trả lời.
- [ ] Sau Phase 8/9: deploy lại một lần trước khi quay video.
