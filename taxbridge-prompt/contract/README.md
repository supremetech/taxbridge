# TaxBridge PoC — API Contract

Nguồn canonical cho DTO, enum, endpoint và fixtures dùng chung giữa
`taxbridge-server` (Flask) và `taxbridge-app` (Flutter). **Đổi contract = sửa ở đây
trước**, rồi mới sửa code hai bên và cập nhật plan.

```text
contract/
├── README.md          quy ước, auth, status/error code, enum, ghi chú Zalo
├── endpoints.md       bảng endpoint ↔ fixture request/response + curl mẫu
└── fixtures/
    ├── *.json         DTO response/request (một bộ dữ liệu demo nhất quán)
    └── zalo/          payload webhook Zalo Bot THẬT + bản normalize nội bộ
```

Bản OpenAPI đọc bằng trình duyệt: `GET /api/docs` (Swagger UI) — spec viết tay ở
`taxbridge-server/functions/app/openapi.yaml`, **sinh ra từ chính contract này**, nên đổi
contract thì sửa file spec luôn (không có bước generate tự động).

Cách dùng:

- **Flutter**: `tool/sync_fixtures.sh` copy `fixtures/` → `assets/fixtures/`;
  `FakeTaxBridgeApi` đọc từ đó khi `--dart-define=USE_MOCK=true`. Không sửa tay bản copy.
- **Backend**: `tests/smoke/smoke.sh` gửi `*_request.json` và so shape response với
  fixture cùng tên; `fixtures/zalo/webhook_*.json` là payload giả cho
  `POST /api/zalo/webhook`.

## 1. Quy ước chung

| Quy ước | Giá trị |
|---|---|
| Base path | `/api` |
| JSON field | `camelCase` |
| Tiền | `int` VND, không float/Decimal |
| Thời gian | ISO-8601 có timezone: `2026-09-11T14:33:00+07:00` |
| Ngày nghiệp vụ | `Asia/Ho_Chi_Minh`; `date`/`dateKey` dạng `YYYY-MM-DD` |
| Success | Trả thẳng DTO, không bọc `data` |
| Error | `{ "code": "...", "message": "..." }` — `code` là contract, `message` thì không |
| Mutation | `PUT`, `confirm`, `reject`, `match`, `classify`, `close-day` trả DTO mới nhất |
| `null` | Field optional không có giá trị trả `null`, không bỏ key. `candidates` luôn có, `[]` khi rỗng |

## 2. Auth

- Register/login trả `Session` có `token` (opaque, prefix `tb_`, không expiry trong PoC).
- Mọi API nghiệp vụ gửi header **`X-Session-Token: <token>`**. Backend resolve
  `accountId`/`businessId` từ `sessions/{token}`; **client không gửi `businessId`**.
- Public (không token): `GET /api/health`, `POST /api/register`, `POST /api/login`,
  `GET /api/zalo-users/unlinked`, `POST /api/zalo/webhook`, `GET /api/docs`,
  `GET /api/openapi.yaml`.
- `401` → app xóa session, về Login.

## 3. Status code và error code

| HTTP | `code` | Khi nào |
|---|---|---|
| 200 | — | thành công |
| 201 | — | `POST /api/register` |
| 204 | — | `POST /api/logout` |
| 400 | `VALIDATION_ERROR` | body/query sai, thiếu field, enum không hợp lệ, `date` sai format |
| 401 | `UNAUTHORIZED` | sai username/password, thiếu hoặc sai token, sai `X-Bot-Api-Secret-Token` |
| 404 | `NOT_FOUND` | event/movement/daily record/zalo user không tồn tại trong business |
| 409 | `USERNAME_TAKEN` | username đã có |
| 409 | `ZALO_USER_LINKED` | `zaloId` đã liên kết account khác |
| 409 | `INVALID_STATE` | confirm event không phải DRAFT, match movement không phải UNMATCHED… |
| 413 | `FILE_TOO_LARGE` | file > 10 MB |
| 415 | `UNSUPPORTED_FILE_TYPE` | không phải JPEG/PNG/M4A |
| 500 | `INTERNAL_ERROR` | lỗi không mong đợi |

AI lỗi khi capture **không** trả 5xx: trả `200` với `CaptureResult.status = FAILED`,
`resultType`/`resultId` = `null`, `error` = mã ngắn: `AI_EXTRACTION_FAILED` (exception OpenAI),
`NO_TRANSACTION` (text/voice không có giao dịch), `UNRECOGNIZED_IMAGE` (ảnh không phải chứng
từ / chuyển khoản). App hiển thị chung "Không xử lý được. Thử lại."

## 4. Enum canonical

```text
Capture.type:          TEXT | AUDIO | IMAGE_RECEIPT | IMAGE_TRANSFER
                       (+ IMAGE_UNKNOWN chỉ nội bộ backend, cho ảnh từ Zalo)
Capture.status:        PROCESSING | DONE | FAILED
Capture.resultType:    EVENT | MONEY_MOVEMENT
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
source:                APP | ZALO          (BusinessEvent, MoneyMovement — nguồn capture)
captureType:           TEXT | AUDIO | IMAGE_RECEIPT | IMAGE_TRANSFER
                       (BusinessEvent, MoneyMovement — copy từ capture; ảnh Zalo lưu type sau khi
                       đã phân loại kind, không lưu IMAGE_UNKNOWN)
```

`source` và `captureType` bắt buộc, không `null`; app dùng để hiện chip nguồn (💬 Zalo /
🎤 Voice / 📷 Ảnh). Không thêm value ở bất kỳ bên nào.

## 5. Bộ dữ liệu demo trong fixtures (nhất quán)

Tất cả fixture mô tả **cùng một business `biz_001`, ngày 2026-09-11**, snapshot cuối
ngày trước khi đóng ngày. `dashboard.json` được tính từ `events.json` +
`money_movements.json` (script sinh có assert), nên mock UI và số thật sẽ khớp:

| Số | Giá trị | Từ đâu |
|---|---|---|
| revenue | 4.820.000 | SALE CONFIRMED: 450k + 1.200k + 2.920k + 250k |
| collected | 4.570.000 | SALE CONFIRMED có PAID (trừ 250k của em Thảo) |
| receivable | 250.000 | revenue − collected |
| expense | 1.230.000 | PURCHASE CONFIRMED: 220k + 1.010k (draft 180k không tính) |
| bankIn | 4.950.000 | mọi movement IN: 450k + 380k + 1.200k + 2.920k |
| draftCount | 1 | `ev_007` |
| unmatchedMoneyCount | 1 | `mov_002` (380k `COC MINH`) |

Fixture "trạng thái tại một thời điểm" (không phải snapshot cuối ngày):

- `event.json` — `ev_001` ngay sau AI: `DRAFT`, `UNPAID` (UC2/UC3 trước confirm).
- `money_movement.json` — `mov_001` ngay sau upload: `UNMATCHED` + 1 candidate (UC4).
- `money_movement_unmatched.json` — `mov_002` 380k, `candidates: []` (UC5 trước classify).
- `money_movement_classified.json` — `mov_002` sau `classify DEPOSIT`.
- `daily_records.json` — 3 ngày: 11/09 (2 warning OPEN), 10/09 (sạch), 09/09 (1 OPEN +
  1 RESOLVED để thấy lịch sử bổ sung sau khi đóng ngày).

### 5.1 Bằng chứng — `evidenceText`, `evidenceUrl`

`BusinessEvent` và `MoneyMovement` có 2 field nullable, luôn có key; backend copy từ capture
lúc tạo, `PUT` không sửa được. App hiện khối **Bằng chứng** ở Event / Movement Detail.

| `captureType` | `evidenceText` | `evidenceUrl` |
|---|---|---|
| `TEXT` | câu gốc người dùng gửi (app hoặc Zalo) | `null` |
| `AUDIO` | transcript | file `.m4a` (Zalo: bản sau remux) |
| `IMAGE_RECEIPT` / `IMAGE_TRANSFER` | `null` | ảnh gốc |

- URL thật là Firebase Storage **download URL có token**:
  `https://firebasestorage.googleapis.com/v0/b/<bucket>/o/captures%2F<businessId>%2F<captureId>.jpg?alt=media&token=<uuid>`.
  **Ai có link đều mở được** — chấp nhận trong PoC (`CLAUDE.md` §4: không làm Security Rules).
- Upload Storage lỗi (emulator local) → `evidenceUrl: null`, capture vẫn DONE.
- Fixtures dùng `asset://demo/<file>` ↔ `assets/demo/<file>` trong app (`receipt.jpg`,
  `transfer_match.jpg`, `transfer_deposit.jpg`, `sale_voice.m4a`) để mock hiển thị offline;
  app: `http` → network, `asset://` → asset. Bản ghi không có file demo tương ứng
  (`ev_003`, `ev_006`, `ev_007`, `mov_003`, `mov_004`) → `evidenceUrl: null` (`ev_003` vẫn có transcript).

## 6. Zalo Bot Platform — payload thật

Lấy từ Firestore `zalo_events` (project `hackathon-42790`, webhook test 10/09/2026).
Cấu trúc trong `fixtures/zalo/webhook_*.json` **giữ nguyên**, chỉ thay `id` và
`display_name` của người test.

```jsonc
{
  "event_name": "message.text.received",        // | message.image.received | message.voice.received
  "message": {
    "date": 1789033572455,                       // epoch MILLISECONDS
    "chat": { "chat_type": "PRIVATE", "id": "a1b2c3d4e5f60718293a" },
    "message_id": "m1a2b3c4d5e6f7081920",
    "from": { "id": "a1b2c3d4e5f60718293a", "is_bot": false, "display_name": "…" },
    "text": "…",                                 // chỉ text
    "photo_url": "https://photo-stal-1.zdn.vn/…jpg",   // chỉ image (+ "caption", "message_type": "CHAT_PHOTO")
    "voice_url": "https://f2-voice-aac-dl.zdn.vn/….aac" // chỉ voice (+ "message_type": "CHAT_VOICE")
  }
}
```

Điểm cần nhớ khi implement (`zalo_service.py`):

| Việc | Chi tiết |
|---|---|
| `zaloId` | `message.from.id` (20 hex). `zalo_users/{zaloId}`, `displayName` = `message.from.display_name`. `chat.id == from.id` với chat PRIVATE; dùng `chat.id` nếu muốn `sendMessage` trả lời. |
| `messageType` | Suy từ field có mặt: `voice_url` → `AUDIO`, `photo_url` → `IMAGE`, `sticker` → `STICKER`, `text` → `TEXT`, còn lại → `OTHER`. Đừng dựa vào `event_name` một mình — Zalo có thể thêm event mới. |
| Sticker & loại lạ | `STICKER` và `OTHER` **vẫn được normalize và vẫn upsert `zalo_users`** — nếu bỏ qua thì user nhắn sticker trước sẽ không bao giờ hiện ở dropdown Register (UC8). Chưa link → vẫn lưu `zalo_unlinked_messages`. Đã link → **không** gọi AI, **không** tạo capture (sticker không có giao dịch). |
| `sticker` | Zalo **không công bố** schema của field này. `normalize` đọc phòng thủ: `sticker` là dict (`url`/`image_url`/`icon_url`/`href`, hoặc `id`), là string, hay `sticker_url`/`sticker_id` phẳng đều lấy được → `stickerUrl`; không đọc được thì `stickerUrl: null` nhưng **vẫn** là `STICKER`. |
| Media URL | **Public, `GET` trực tiếp không cần token** (đã test 11/09: ảnh JPEG 1920×2560 ~690 KB; voice 21 KB). Có thể hết hạn → tải ngay trong request webhook. |
| Voice format | **Raw ADTS AAC** (16 kHz mono, `.aac`). **Đã test 11/09 với OpenAI**: gửi `.aac` → `400 Unsupported file format aac`; đổi tên `.m4a` không remux → `400 corrupted`. **Bắt buộc remux** sang M4A không re-encode (`-c:a copy`, ~20 ms). **Đã deploy thử lên Functions gen2 (python312, asia-southeast1) 11/09**: `imageio-ffmpeg` chạy được (binary `ffmpeg-linux-x86_64-v7.0.2` trong `/layers/google.python.pip/...`), remux 10–175 ms, secret `OPENAI_API_KEY` mount OK, raw POST body đi qua OK, transcript TTS ra đúng. Cold start tổng ~17 s (instance 23 s tuổi, transcribe lần đầu 6,5 s); warm ~1 s. Snippet ở dưới. |
| `date` | epoch ms → `occurredAt` ISO `+07:00`. |
| Body rỗng | Zalo/health probe có thể gọi webhook với body rỗng, không `content-type` (đã thấy 1 lần). Trả `200`, không parse. |
| Secret | Header `X-Bot-Api-Secret-Token` so khớp thẳng với `ZALO_WEBHOOK_SECRET`; sai → `401`. |
| Response | Luôn `200 {"ok": true}` sau khi lưu, kể cả AI lỗi (ghi `capture.error`), để Zalo không gửi lại. |
| Kích thước | Bản thật ~270–420 byte/message; không cần giới hạn đặc biệt. |

Remux + transcribe (đường chung cho app upload M4A và Zalo AAC):

```python
import subprocess, tempfile, imageio_ffmpeg

def aac_to_m4a(aac_bytes: bytes) -> bytes:
    exe = imageio_ffmpeg.get_ffmpeg_exe()          # binary bundle, chạy được trên Functions
    with tempfile.TemporaryDirectory() as d:        # /tmp của Functions ghi được
        src, dst = f"{d}/in.aac", f"{d}/out.m4a"
        open(src, "wb").write(aac_bytes)
        subprocess.run([exe, "-v", "error", "-y", "-i", src, "-c:a", "copy", dst], check=True)
        return open(dst, "rb").read()

# transcription: gpt-transcribe (model file-transcription OpenAI khuyến nghị từ 07/2026;
# chỉ nhận `languages` số nhiều + `keywords`). Fallback gpt-4o-transcribe + language="vi"
# (đã đo đúng 11/09). whisper-1 nghe nhầm "truyền khoản" — không dùng.
text = client.audio.transcriptions.create(
    model="gpt-transcribe", file=("voice.m4a", m4a_bytes),
    prompt="Chủ hộ kinh doanh Việt Nam đọc một giao dịch bán/mua hàng.",
    extra_body={"languages": ["vi"], "keywords": ["chuyển khoản", "tiền mặt", "nghìn", "triệu"]}).text
```

`fixtures/zalo/normalized_*.json` là shape nội bộ sau normalize (plan backend mục 9):
`zaloId, displayName, chatId, messageId, messageType, text, imageUrl, audioUrl, stickerUrl,
sentAt, rawPayload`.

⚠️ `webhook_sticker.json` / `normalized_sticker.json` là payload **dựng tay** theo tài liệu
SDK (`event_name: message.sticker.received`, dữ liệu ở `message.sticker`), chưa bắt được
message sticker thật — khác ba bộ text/image/voice lấy từ webhook thật 10/09. Bắt được
payload thật thì thay lại và chỉnh `_sticker_url` nếu tên field khác.

Payload `user_send_text` + `app_id` là format **Zalo OA API** (bản cũ hỗ trợ song song);
PoC **không** dùng OA, bỏ qua nếu gặp.
