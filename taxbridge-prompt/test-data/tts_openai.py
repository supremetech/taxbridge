#!/usr/bin/env python3
"""
Phương án 2 cho audio: sinh giọng bằng OpenAI TTS.

Chạy trên MÁY CỦA BẠN (môi trường cloud của phiên này bị chặn api.openai.com):

    pip install openai
    export OPENAI_API_KEY=sk-...
    python3 tts_openai.py

Lưu ý thật lòng: TTS không tái hiện được giọng miền Trung và tiếng ồn thật.
Case A2 (và lý tưởng là cả A1–A3) nên thu bằng giọng người theo
`audio_scripts.md`; TTS chỉ nên dùng khi cần chạy thử pipeline ngay.
"""
import os, pathlib
from openai import OpenAI

OUT = pathlib.Path("out/evidence"); OUT.mkdir(parents=True, exist_ok=True)
client = OpenAI(api_key=os.environ["OPENAI_API_KEY"])

CLIPS = [
    ("synthetic_voice_A1.mp3", "coral",
     "Bán cho anh Minh ba hộp tỏi đen cô đơn, bảy trăm hai mươi nghìn, anh ấy trả tiền mặt luôn rồi.",
     "Giọng nữ trung niên người Việt, nói nhanh và tự nhiên như đang ghi chú vội giữa lúc bán hàng."),
    ("synthetic_voice_A2.mp3", "sage",
     "Bán cho o Hương một cân mắc khén, bốn trăm nghìn, o nớ nói chút nữa chuyển khoản.",
     "Giọng nữ người Việt, chất giọng miền Trung, nói hơi nhanh, ngữ điệu đời thường."),
    ("synthetic_voice_A3.mp3", "coral",
     "Chị Thu lấy hai hộp trà ô long... à không, ba hộp, tổng sáu trăm nghìn, chị ấy chuyển khoản sau.",
     "Giọng nữ người Việt, có ngập ngừng và tự sửa lại giữa câu, nhịp nói không đều."),
    ("synthetic_voice_A4.mp3", "coral",
     "Ừ trưa nay ăn cơm chỗ cũ đi, tầm mười một giờ rưỡi nhé, để tí nữa tính.",
     "Giọng nữ người Việt, nói chuyện phiếm thoải mái, không phải đang ghi chép gì."),
]

for fname, voice, text, instr in CLIPS:
    with client.audio.speech.with_streaming_response.create(
        model="gpt-4o-mini-tts", voice=voice, input=text, instructions=instr,
    ) as r:
        r.stream_to_file(OUT / fname)
    print("->", fname)

print("\nSau đó tạo bản nhiễu cho A2:")
print("  ./mix_noise.sh out/evidence/synthetic_voice_A2.mp3 "
      "out/evidence/synthetic_voice_A2_noisy.m4a 12")
