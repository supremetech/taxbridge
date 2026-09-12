# Bot trả lời trong Zalo

Chủ hộ nhắn cho bot (text / ảnh / voice) và nhận ngay một câu trả lời trong chính Zalo: đã ghi
nháp gì, tiền vào bao nhiêu và cần mở app làm gì; chưa liên kết thì được hướng dẫn. Không có UI
trong app (Phase 2 ⑤). Nội dung câu trả lời và API: `contract/README.md` §6.1; code: plan BE §16.

## Sub-features

- `reply-unlinked` user chưa link → hướng dẫn kèm `displayName`.
- `reply-event` capture DONE EVENT → `✅ Đã ghi nháp: …`.
- `reply-movement` capture DONE MOVEMENT → `🏦 Tiền vào …` + có / không candidate.
- `reply-failed` capture FAILED → `❌ Chưa đọc được giao dịch …`.
- `reply-silent` sticker / loại lạ → không trả lời; token rỗng → log, không lỗi.

## How to get to it (user POV)

- Trên điện thoại: mở chat với bot TaxBridge → nhắn `bán 2 hộp collagen 300k ck` → bot trả lời
  trong ~5–10 s → mở app → Home (Giao dịch badge +1).
- Gửi ảnh chuyển khoản vào chat → bot: `🏦 Tiền vào 380.000đ từ NGUYEN VAN MINH — chưa rõ là khoản gì. Mở app để phân loại.`

## Handles

| Màn hình | Loại | Nhãn |
|---|---|---|
| Zalo chat | tin nhắn bot | đúng 5 mẫu ở `contract/README.md` §6.1 (prefix `✅` / `🏦` / `❌`) |

## Driving it with curl

Preconditions: backend local có `ZALO_BOT_TOKEN` trong `.env` root (không có → mỗi bước dưới chỉ
thấy log `ZALO_BOT_TOKEN rỗng — bỏ qua reply`); `S="X-Bot-Api-Secret-Token: $ZALO_WEBHOOK_SECRET"`;
`fixtures/zalo/webhook_text.json` với `from.id` = Zalo **thật** của người test (chỉ khi muốn thấy
tin nhắn tới điện thoại; id giả → sendMessage trả 4xx, chỉ có log).

- **Chưa link.** Xóa link (hoặc dùng id chưa link) → `curl -s $B/api/zalo/webhook -H "$S" -H "$J" -d @contract/fixtures/zalo/webhook_text.json`
  → `200 {"ok":true}`; log Flask: `sendMessage → 200 …`; điện thoại nhận `TaxBridge chưa liên kết Zalo này. …`.
- **Đã link, text.** Register với `zaloId` đó → gửi lại `webhook_text.json` → log `sendMessage → 200`,
  điện thoại nhận `✅ Đã ghi nháp: Bán hàng 450.000đ · chị Lan · CK, chưa thu. Mở app để xác nhận.`;
  `curl -s "$B/api/events?status=DRAFT" -H "$H"` có draft `source: ZALO`.
- **Ảnh CK.** `webhook_image.json` (media = ảnh 380k trên Storage, `ZALO_MEDIA` như smoke) →
  `🏦 Tiền vào 380.000đ từ … — chưa rõ là khoản gì. Mở app để phân loại.`
- **Sticker.** `webhook_sticker.json` → `200`, **không** có dòng `sendMessage` trong log.
- **Bằng chứng.** Ảnh chụp màn hình chat Zalo có 3 câu trả lời + log Flask 3 dòng `sendMessage → 200`.
  Ghi shape response thật vào `contract/README.md` §6.1.
