# Kịch bản thu âm — 4 case AUDIO

Ưu tiên **thu bằng giọng người thật** (điện thoại, app Ghi âm, xuất M4A). Tổng thời
gian thu khoảng 15 phút. Lý do không dùng TTS: case A2 kiểm tra giọng miền Trung +
tiếng ồn nền, và A3 kiểm tra hiện tượng nói vấp tự sửa — TTS không tái hiện được
hai thứ này, dùng TTS sẽ cho ra con số accuracy đẹp hơn thực tế.

Nếu cần chạy thử pipeline ngay trước khi kịp thu: `tts_openai.py` (chạy trên máy
bạn, dùng đúng OPENAI_API_KEY của dự án).

Điều kiện thu chung: cầm điện thoại cách miệng 20–30cm, nói như đang ghi chú vội
giữa lúc bán hàng — **không đọc như đọc văn bản**.

---

## A1 — Bán hàng, giọng rõ, phòng yên tĩnh

> "Bán cho anh Minh ba hộp tỏi đen cô đơn, bảy trăm hai mươi nghìn, anh ấy trả tiền mặt luôn rồi."

Người đọc: giọng chuẩn (Bắc hoặc Nam đều được). Phòng yên tĩnh.
File: `synthetic_voice_A1.m4a`

---

## A2 — Bán hàng, giọng miền Trung, có tiếng ồn nền

> "Bán cho cô Hương một cân mắc khén, bốn trăm nghìn, cô nớ nói chút nữa chuyển khoản."

Người đọc: **giọng miền Trung thật** (Nghệ An / Hà Tĩnh / Quảng Bình). Giữ nguyên
từ địa phương "o", "o nớ" — đây chính là thứ cần test, không đổi thành "cô", "cô ấy".

Thu ở phòng yên tĩnh trước, rồi trộn nhiễu bằng script để kiểm soát được mức ồn:

```bash
./mix_noise.sh <file_thu_sach>.m4a out/evidence/synthetic_voice_A2.m4a 12
```

`12` là SNR (dB). Muốn dò ngưỡng gãy của ASR thì chạy thêm mức 18 (ồn nhẹ) và
6 (rất ồn) thành 3 biến thể.
File: `synthetic_voice_A2.m4a`

---

## A3 — Nói vấp, tự sửa số giữa câu

> "Chị Thu lấy hai hộp trà ô long... *(ngập ngừng thật, khoảng 1 giây)* ...à không, ba hộp, tổng sáu trăm nghìn, chị ấy chuyển khoản sau."

Quan trọng: ngập ngừng phải là khoảng lặng thật, không phải đọc liền mạch.
Kết quả đúng là **ba hộp / 600.000** — số chốt cuối cùng, không phải số nói đầu tiên.
File: `synthetic_voice_A3.m4a`

---

## A4 — Không có nghiệp vụ (bẫy)

> "Ừ trưa nay ăn cơm chỗ cũ đi, tầm mười một giờ rưỡi nhé, để tí nữa tính."

Nói thoải mái như nói chuyện phiếm. Case này kiểm tra AI **không bịa ra giao dịch**
khi input không chứa nghiệp vụ nào. Lưu ý câu này có chứa số ("mười một giờ rưỡi")
để bẫy việc bắt số thành số tiền.
File: `synthetic_voice_A4.m4a`

---

## Sau khi thu xong

Đặt file vào `test-data/evidence/` đúng tên trên, rồi đối chiếu với
`cases/A1.json` … `cases/A4.json` — expected output đã viết sẵn ở đó.
