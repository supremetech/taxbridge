# Demo assets dùng chung

| File | Nội dung | Dùng cho |
|---|---|---|
| `sale_voice.m4a` | TTS (`gpt-4o-mini-tts`, voice nova): "Bán cho chị Lan ba hộp collagen, tổng bốn trăm năm mươi nghìn, khách chuyển khoản." 6,2 s, AAC-LC 24 kHz mono trong container M4A | App: `assets/demo/sale_voice.m4a` (UC3, nút "Dùng file demo"); backend smoke `POST /api/captures type=AUDIO` |
| `sale_voice.aac` | Cùng nội dung, **raw ADTS AAC** — đúng định dạng Zalo gửi trong `voice_url` | Backend: test đường Zalo voice → remux → transcribe |

Kết quả transcription đã đo 11/09/2026 (sau remux sang M4A; `language=vi` với model 4o, `languages[]=vi` với `gpt-transcribe`):

| Model | Kết quả | Thời gian |
|---|---|---|
| `gpt-4o-transcribe` | "Bán cho chị Lan 3 hộp collagen, tổng 450 nghìn, khách chuyển khoản." — **đúng, ra số** | 2,7 s |
| `gpt-4o-mini-transcribe` | "…ba hộp collagen, tổng bốn trăm năm mươi nghìn, khách chuyển khoản." — đúng, chữ | 2,0 s |
| `whisper-1` | "…tổng 450.000 khách **truyền** khoản." — sai từ khóa | 0,8 s |
| **`gpt-transcribe`** (07/2026, khuyến nghị thay `gpt-4o-transcribe`) — **đã chốt dùng** | "Bán cho chị Lan 3 hộp collagen, tổng 450 nghìn, khách chuyển khoản." — **đúng, ra số**, giống hệt `gpt-4o-transcribe`; kết quả y hệt dù có hay không `prompt`/`keywords`; `languages: [{"code":"vi"}]` | 1,7–2,6 s (đo 3 lần, 11/09 tối) |
| `gpt-transcribe` qua đường Zalo (`sale_voice.aac` → `ffmpeg -c:a copy` → m4a) | Cùng transcript đúng; gửi raw `.aac` thẳng vẫn `400 Unsupported file format aac` | 1,5 s |

Raw `.aac` gửi thẳng: `400 Unsupported file format aac`. Đổi tên `.m4a` mà không remux:
`400 Audio file might be corrupted`. → **Phải remux** (`ffmpeg -c:a copy`, ~20 ms).

| `transfer_match.jpg` | Màn "Chuyển khoản thành công" 450.000 VND, nguồn `NGUYEN THI LAN`, người nhận `MAI ANH TUAN`, nội dung `LAN 3HOP` (1800×3200, render AppKit 11/09) | UC4: app `assets/demo/`, smoke `type=IMAGE_TRANSFER` |
| `transfer_deposit.jpg` | Cùng layout, 380.000 VND, nguồn `NGUYEN VAN MINH`, nội dung `COC MINH` | UC5 (hero) |
| `receipt.jpg` | Hóa đơn bán lẻ "Cửa hàng bao bì ABC": túi giấy + hộp carton + băng keo, tổng 220.000đ, **TIỀN MẶT** (1800×2600) | UC6: `type=IMAGE_RECEIPT` → PURCHASE 220k CASH |

Ảnh chưa test qua vision model; nếu AI đọc sai thì chỉnh font/cỡ chữ rồi render lại.
