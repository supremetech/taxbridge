# TaxBridge — Chuẩn bị trước Build day (12/09/2026)

_Agents, Everywhere: Bots, Channels & More — AI Tinkerers Đà Nẵng × OpenAI_

## 1. Thực tế thời gian

| Mốc | Ý nghĩa |
|---|---|
| 09:15 | Briefing + starter kit. Team formation **khóa 11:15** — chỉ team đã đăng ký mới được submit. |
| 09:30–16:00 | Build **6,5 giờ**. |
| 16:00 | Form khóa: title, description, **public GitHub repo**, **video 2 phút**, social post tag sponsor. |
| 16:00–16:45 | Panel chấm **từ video**, chọn 5–6 finalist. |
| 17:00 | Finalist demo live 2 phút + Q&A. |

```text
09:30–14:30  code (5h)                                  14:30–15:30  quay + cắt + upload video
15:30–15:50  repo public, README, form, social post     15:50–16:00  đệm
```

**Mọi thứ không phải "code tính năng" xong tối 11/09.** Video là sản phẩm chính; app là đạo
cụ. Điểm hợp đề bài cần nói trong video/description: agent sống trong **Zalo** và
**camera/mic tại quầy** — "belongs somewhere new", không phải một chat window riêng.

## 2. Setup tối 11/09

### Chưa xong

| Việc | Lệnh / ghi chú |
|---|---|
| Portal: join team, đọc handbook (quy định code có sẵn, tiêu chí chấm, video guidance), claim credits, chụp form submission | Ghi vào mục 7. Nếu event cấp OpenAI key → `firebase functions:secrets:set OPENAI_API_KEY` lại. |
| `gcloud` đang trỏ `synchire` | `gcloud config set project hackathon-42790 && gcloud auth application-default login` |
| Secret Zalo: `ZALO_WEBHOOK_SECRET` **đã set** (11/09); còn `ZALO_BOT_TOKEN` | `firebase functions:secrets:set ZALO_BOT_TOKEN --project hackathon-42790` (thiếu → deploy fail vì `secrets=[...]`) |
| OpenAI key local | **Đã có** `taxbridge-server/.env` (gitignored) với `OPENAI_API_KEY`, `GCLOUD_PROJECT`, `ZALO_WEBHOOK_SECRET`; key đã verify, account có `gpt-5.6-terra`/`gpt-transcribe`. Còn: kiểm tra credit đủ ~100 call |
| ngrok chưa cài | `brew install ngrok` → `ngrok config add-authtoken …` → lấy **static domain** để URL không đổi (`API_BASE_URL` + Zalo webhook) |
| Zalo webhook đang trỏ URL cũ (404) | Ghi lại URL hiện tại; sáng mai `setWebhook` sang ngrok, 14:00 sang Functions |
| 2 iPhone | Cắm, trust, Developer Mode, Xcode Team + bundle `vn.supremetech.taxbridge.poc`, build app trống lên **cả 2** |
| GitHub 2 repo đang PRIVATE | 15:30: `gh repo edit supremetech/taxbridge-server --visibility public --accept-visibility-change-consequences` (tương tự app) |
| CocoaPods warning UTF-8 | `export LANG=en_US.UTF-8` vào `~/.zshrc` |
| Wifi yếu | `pip download` deps vào cache, `flutter pub get` sẵn; hotspot 4G cho ngrok / Zalo |

Đã OK, không cần đụng: Firebase `hackathon-42790` (Blaze, `asia-southeast1`, đã dọn trắng
0 function / Firestore trống / bucket trống), Flutter 3.47, Xcode 26.6, ffmpeg 7.1, gh,
Python 3.12 tại `/opt/homebrew/bin/python3.12` (venv **phải** dùng bản này). Máy dự phòng là
iPhone thứ 2, không cài Android.

### Lệnh setup 2 repo

```bash
cd taxbridge-server && git checkout poc-new
python3.12 -m venv functions/venv && source functions/venv/bin/activate
pip install firebase-functions firebase-admin flask openai pydantic python-dotenv requests imageio-ffmpeg
flask --app app.flask_app:create_app run --port 8787     # sau khi có skeleton
ngrok http --domain=<static>.ngrok-free.app 8787
```

```bash
cd taxbridge-app && git checkout poc-new
flutter create . --org vn.supremetech --project-name taxbridge_app --platforms ios,android
flutter pub add flutter_riverpod go_router dio image_picker record shared_preferences intl
flutter run -d <iphone>                                   # chốt signing tối nay
flutter build ios --release                               # đo thời gian build release
```

Sponsor tag social post: OpenAI · Ecomdy · SupremeTech · Dat.Bike · CopilotKit · OpenRouter ·
Exa · Auth0 · DNES · Ambiguous AI · Swiss EP · Trigger.dev · Mozilla · Google Cloud Run;
co-organizer dewly · DSAC · GDG Miền Trung · DISSC.

## 3. Làm sẵn tối 11/09

Nếu handbook **cấm** pre-build code → chỉ giữ phần tài liệu / asset, bỏ hai dòng skeleton.

- [x] `contract/` README + endpoints + 28 fixtures nhất quán.
- [x] `demo-assets/sale_voice.{m4a,aac}` + đo transcription: `gpt-transcribe` đúng (đã chốt), `gpt-4o-transcribe` đúng (fallback).
- [x] Voice Zalo raw AAC → remux bằng `imageio-ffmpeg`, đã chạy OK trên Functions.
- [ ] 3 ảnh demo: `transfer_match.jpg` (450.000đ, `LAN 3HOP`, `NGUYEN THI LAN`),
      `transfer_deposit.jpg` (380.000đ, `COC MINH`), `receipt.jpg` (bao bì 220.000đ, tiền
      mặt). Mockup / ảnh giả lập, **không dùng tài khoản thật**.
- [ ] Chạy 3 ảnh demo qua `openai_client.py` (`gpt-5.6-terra`), đối chiếu số với UC 4–6.
      (Voice đã đo xong.)
- [ ] Video script (mục 5) + storyboard; chọn cách quay; test upload YouTube unlisted.
- [ ] Draft title, description, README (2 repo), social post.
- [ ] Skeleton backend Phase 0 (plan BE §11) + **deploy thử 1 lần** → URL thật, multipart qua wrapper.
- [ ] Skeleton Flutter Phase 0 (plan FE §9) + build lên 2 iPhone.
- [ ] Khung `tests/smoke/smoke.sh`; seed script (1 account demo + 2–3 daily record cũ).
- [ ] Sạc pin, hotspot 4G, ngủ trước 24:00.

Giữ commit history rõ ràng trên `poc-new`.

## 4. Build day — time-box

| Giờ | Backend | Flutter | Người thứ 3 |
|---|---|---|---|
| 09:30–10:15 | **Tracer bullet**: Flask + ngrok + `POST /api/captures` TEXT → OpenAI → event DRAFT | Text capture → Event Detail → confirm (mock → ngrok) | Portal / team, máy quay, credits |
| 10:15–11:30 | Register / login, events list / PUT / reject, dashboard 7 số | Login / Register, Home 4 card + `bankIn` + badge, Events | Seed data, `smoke.sh` UC1–UC2 |
| 11:30–12:30 | Receipt + transfer extraction, movement, candidate, match, classify | Image picker, Movement list / detail, match / classify | Kiểm tra ảnh demo đọc đúng số |
| 12:30–13:00 | Ăn + voice | Ăn + voice record | Ăn |
| 13:00–14:00 | Close day, daily records, warning; Zalo webhook; `source`/`captureType` trên event/movement | Close day, history, warning navigate; wow 1–4 nếu kịp (plan FE §9 Phase 6b) | Quay thử từng cảnh |
| 14:00–14:30 | Deploy Functions, `MIN_INSTANCES=1`, trỏ Zalo webhook, seed prod | Release build lên iPhone demo | Chạy 9 UC, ghi bug |
| **14:30** | **FEATURE FREEZE** — chỉ fix bug làm hỏng video | | |
| 14:30–15:30 | Hỗ trợ quay, sửa data | Cầm máy demo | Quay 2–3 take, cắt, upload |
| 15:30–15:50 | Repo public, README | Repo public, README | Submit form, social post |
| 15:50–16:00 | Đệm | Đệm | Kiểm tra form đã lock đúng |

**11:30 mà UC2 chưa chạy end-to-end thật → dừng, quay video bằng mock / cached, không cố.**

## 5. Video 2 phút

| Giây | Cảnh | Hình |
|---|---|---|
| 0–12 | Vấn đề: một ngày bán hàng nằm rải trong lời nói, ảnh hóa đơn, báo có, trí nhớ chủ quán | Quầy hàng / text overlay |
| 12–30 | Nói "bán cho chị Lan 3 hộp collagen 450 nghìn chuyển khoản" → draft SALE → confirm → Doanh thu 450k, Còn phải thu 450k | Capture → Event Detail → Home |
| 30–48 | Chụp báo có 450k → app đề xuất ghép đơn chị Lan → Ghép → Tiền đã thu 450k, Còn phải thu 0 | Movement Detail → Home |
| 48–62 | Chụp phiếu bao bì 220k → PURCHASE → confirm → Chi phí 220k | Event Detail → Home |
| 62–92 | **Hero**: chụp báo có 380k `COC MINH` → Tiền vào NH +380k, badge 1 → "khoản này là gì?" → Đặt cọc → badge 0, banner **"Tiền vào +380.000đ · Doanh thu không đổi ✓"**, Thuế khoán ước tính không đổi | Movement Detail (zoom ảnh CK trong khối Bằng chứng 1 s) → Home (zoom banner + 2 số) |
| 92–108 | Zalo: nhắn bot "bán 2 hộp 300 nghìn tiền mặt" từ điện thoại 2 → app tự cập nhật (≤ 8 s) → draft mới có chip 💬 Zalo | Zalo + app cạnh nhau |
| 108–118 | Đóng ngày → summary + warning → mở lại từ lịch sử | Close Day → History |
| 118–120 | "TaxBridge turns messy counter activity into an evidence-backed ledger" + logo | Text overlay |

Quay: iPhone Screen Recording hoặc QuickTime → New Movie Recording qua USB (nét hơn, không
thanh đỏ) — thử cả hai tối nay. Zalo quay bằng điện thoại 2 hoặc Zalo Desktop. Voice-over
thu riêng, ghép `ffmpeg -i screen.mov -i vo.m4a -c:v copy -map 0:v -map 1:a -shortest out.mp4`.
Cut / overlay iMovie hoặc CapCut; 4 title card sẵn. **Quay từng cảnh riêng**, không 1 take.
iPhone demo: tắt notification, sạc đầy, sáng tối đa, bỏ auto-lock.

## 6. Rủi ro & fallback

| Rủi ro | Fallback |
|---|---|
| OpenAI chậm / lỗi lúc quay | Đổi model fallback trong `config.py` (`gpt-5.6-luna` / `gpt-4o-transcribe`); quay lại take |
| ngrok rớt | Functions bản 14:00 với `MIN_INSTANCES=1`; launch config `prod` |
| iPhone demo hỏng / signing | iPhone 2 đã build; cùng lắm simulator + "Dùng file demo" |
| Zalo webhook không trỏ được | `smoke.sh` gọi webhook giả; quay màn Zalo riêng rồi ghép |
| Multipart qua Functions wrapper lỗi | Quay bằng ngrok + Flask local; Functions chỉ để repo "deploy được" |
| Repo private lúc submit | Lệnh public ở mục 2; người thứ 3 phụ trách 15:30 |
| Wifi yếu | pip / pub cache + hotspot 4G |

## 7. Ghi chú từ handbook (điền sau khi đọc)

- Quy định code có sẵn: …
- Tiêu chí chấm địa phương: …
- Video guidance: …
- Credits đã claim / model được cấp: …
- Starter repo: …
