#!/usr/bin/env python3
"""Mô phỏng ảnh bị nén khi khách gửi qua Zalo cho chủ shop."""
import pathlib
from PIL import Image

EV = pathlib.Path("/home/claude/tb/out/evidence")

# (file gốc, tên file mới, tỉ lệ resize, chất lượng JPEG)
JOBS = [
    ("synthetic_transfer_M2.png", "synthetic_transfer_M2.jpg", 0.75, 72),
    ("synthetic_transfer_M5.png", "synthetic_transfer_M5.jpg", 0.85, 62),
]

for src, dst, scale, q in JOBS:
    p = EV / src
    im = Image.open(p).convert("RGB")
    w, h = im.size
    im = im.resize((int(w * scale), int(h * scale)), Image.LANCZOS)
    im.save(EV / dst, "JPEG", quality=q, optimize=True)
    p.unlink()  # chỉ giữ bản đã nén, đúng như chủ shop thực sự nhận được
    print(f"{dst}  {im.size[0]}x{im.size[1]}  q={q}")
