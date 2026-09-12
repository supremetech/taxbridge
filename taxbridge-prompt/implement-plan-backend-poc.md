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
   `occurredAt` của cả event lẫn movement = now() (`Asia/Ho_Chi_Minh`), không lấy từ AI.
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

class TransferExtraction(BaseModel):
    direction: Literal["IN", "OUT"]
    amount: int
    counterparty: Optional[str]
    memo: Optional[str]
    # Không có occurredAt: movement luôn lấy now(). Ảnh demo tạo tối 11/09 in ngày 11/09,
    # nếu đọc ngày trên ảnh thì movement rơi khỏi dashboard hôm nay (12/09) → hero hỏng.

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
  - Không đọc ngày giờ trên ảnh (`occurredAt = now()`, mục 4).
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
2. Body rỗng / không có message / không có text|photo_url|voice_url → 200 {"ok": true}.
3. Normalize → shape zalo/normalized_*.json; upsert zalo_users/{zaloId} (displayName, lastSeenAt).
4. linkedBusinessId == null → lưu zalo_unlinked_messages/{messageId} → 200.
5. Đã link → text: process_capture(TEXT)
             photo_url: GET bytes → process_capture(IMAGE_UNKNOWN)
             voice_url: GET bytes → aac_to_m4a → process_capture(AUDIO)
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
