#!/usr/bin/env python3
"""Sinh ảnh hóa đơn / chứng từ SYNTHETIC cho case R1–R3."""
import asyncio, pathlib
from playwright.async_api import async_playwright
from PIL import Image, ImageFilter, ImageEnhance
import numpy as np

OUT = pathlib.Path("/home/claude/tb/out/evidence"); OUT.mkdir(parents=True, exist_ok=True)
F = "'Liberation Sans','DejaVu Sans',sans-serif"
FM = "'Liberation Mono','DejaVu Sans Mono',monospace"
MARK = '<div class="synth">SYNTHETIC TEST FIXTURE — KHÔNG PHẢI CHỨNG TỪ THẬT</div>'

# ── R1: phiếu bán hàng in sẵn, rõ nét ─────────────────────────────────────────
R1 = f"""
<style>
 *{{margin:0;padding:0;box-sizing:border-box}}
 body{{width:720px;height:960px;background:#EDEAE3;font-family:{F};padding:28px}}
 .pg{{background:#fff;height:100%;padding:34px 38px;box-shadow:0 2px 10px rgba(0,0,0,.16);position:relative}}
 .hd{{text-align:center;border-bottom:2px solid #222;padding-bottom:13px}}
 .co{{font-size:19px;font-weight:800;letter-spacing:.4px}}
 .ad{{font-size:12.5px;color:#444;margin-top:5px;line-height:1.5}}
 h2{{text-align:center;font-size:23px;font-weight:800;margin-top:20px;letter-spacing:2px}}
 .meta{{display:flex;justify-content:space-between;font-size:13px;margin-top:9px;color:#333}}
 .cust{{font-size:13.5px;margin-top:18px;line-height:1.9}}
 .cust b{{font-weight:700}}
 table{{width:100%;border-collapse:collapse;margin-top:14px;font-size:13px}}
 th{{background:#F0F0F0;border:1px solid #999;padding:8px 7px;font-size:12px;text-align:center}}
 td{{border:1px solid #999;padding:8px 7px}}
 .r{{text-align:right}} .c{{text-align:center}}
 .tot td{{font-weight:800;font-size:14.5px;background:#FAFAFA}}
 .words{{font-size:13px;font-style:italic;margin-top:11px}}
 .sig{{display:flex;justify-content:space-around;margin-top:46px;font-size:12.5px;text-align:center;color:#222}}
 .sig div b{{display:block;font-weight:700;margin-bottom:56px}}
 .synth{{position:absolute;bottom:12px;left:0;right:0;text-align:center;font-size:9px;color:#BBB}}
</style>
<div class="pg">
  <div class="hd">
    <div class="co">CƠ SỞ CHẾ BIẾN HẠT ĐIỀU BÌNH PHƯỚC</div>
    <div class="ad">Địa chỉ: 128 Quốc lộ 14, P. Tân Đồng, TP. Đồng Xoài<br>
      Điện thoại: 0271 3xxx xxx &nbsp;·&nbsp; MST: 38xxxxxxx1 (mẫu)</div>
  </div>
  <h2>PHIẾU BÁN HÀNG</h2>
  <div class="meta"><span>Số: PBH-2026/0915</span><span>Ngày 11 tháng 09 năm 2026</span></div>
  <div class="cust">
    <b>Khách hàng:</b> Hộ kinh doanh Đặc sản Tây Bắc Hương Núi<br>
    <b>Địa chỉ:</b> Số 47 đường Nguyễn Lương Bằng, TP. Hà Nội<br>
    <b>Hình thức thanh toán:</b> Chuyển khoản — đã thanh toán
  </div>
  <table>
    <tr><th style="width:8%">STT</th><th>Tên hàng hóa</th><th style="width:11%">ĐVT</th>
        <th style="width:11%">SL</th><th style="width:18%">Đơn giá</th><th style="width:20%">Thành tiền</th></tr>
    <tr><td class="c">1</td><td>Hạt điều rang muối loại A</td><td class="c">kg</td>
        <td class="c">4</td><td class="r">300.000</td><td class="r">1.200.000</td></tr>
    <tr><td class="c">2</td><td>Hạt điều vỡ đôi (làm quà tặng)</td><td class="c">kg</td>
        <td class="c">1</td><td class="r">300.000</td><td class="r">300.000</td></tr>
    <tr class="tot"><td colspan="5" class="r">TỔNG CỘNG</td><td class="r">1.500.000</td></tr>
  </table>
  <div class="words">Bằng chữ: Một triệu năm trăm nghìn đồng chẵn.</div>
  <div class="sig"><div><b>Người mua hàng</b>(Ký, ghi rõ họ tên)</div>
                   <div><b>Người bán hàng</b>(Ký, ghi rõ họ tên)</div></div>
  {MARK}
</div>
"""

# ── R2: hóa đơn máy in nhiệt, in mờ ───────────────────────────────────────────
R2 = f"""
<style>
 *{{margin:0;padding:0;box-sizing:border-box}}
 body{{width:420px;height:820px;background:#2A2A28;font-family:{FM};padding:26px 70px}}
 .pg{{background:#F6F4EE;height:100%;padding:22px 16px;font-size:12.5px;line-height:1.62;color:#3A3A38;position:relative}}
 .c{{text-align:center}} .b{{font-weight:700}}
 .big{{font-size:15px;font-weight:700;letter-spacing:1px}}
 .dash{{border-top:1px dashed #8A8A86;margin:9px 0}}
 .row{{display:flex;justify-content:space-between;gap:8px}}
 .tot{{font-size:14.5px;font-weight:700}}
 .synth{{position:absolute;bottom:7px;left:0;right:0;text-align:center;font-size:8px;color:#B4AFA4}}
</style>
<div class="pg">
  <div class="c big">CUA HANG BAO BI MINH LONG</div>
  <div class="c">So 12 ngo 84 Chua Lang - Ha Noi</div>
  <div class="c">DT: 0243 xxx xxxx</div>
  <div class="dash"></div>
  <div class="c b">HOA DON BAN LE</div>
  <div class="row"><span>So HD: 004871</span><span>11/09/26 14:25</span></div>
  <div class="dash"></div>
  <div class="row b"><span>Ten hang</span><span>T.tien</span></div>
  <div class="row"><span>Tui zip 15x25 (100c)</span><span>75.000</span></div>
  <div class="row"><span>Tem nhan dan SP (500c)</span><span>60.000</span></div>
  <div class="row"><span>Bang dinh trong 5cm x3</span><span>30.000</span></div>
  <div class="row"><span>Tui giay quai xoan x10</span><span>20.000</span></div>
  <div class="dash"></div>
  <div class="row tot"><span>TONG CONG</span><span>185.000</span></div>
  <div class="row"><span>Tien mat</span><span>200.000</span></div>
  <div class="row"><span>Tien thoi</span><span>15.000</span></div>
  <div class="dash"></div>
  <div class="c">Cam on quy khach!</div>
  <div class="c">Hen gap lai</div>
  {MARK}
</div>
"""

# ── R3: ảnh chụp nhãn sản phẩm — không phải chứng từ, cố ý mơ hồ ──────────────
R3 = f"""
<style>
 *{{margin:0;padding:0;box-sizing:border-box}}
 body{{width:640px;height:800px;background:#6E6257;display:flex;align-items:center;justify-content:center;font-family:{F}}}
 .lbl{{width:400px;background:#F3E9D2;border:3px solid #6B3F1D;border-radius:10px;padding:28px 24px;text-align:center;
      box-shadow:0 14px 34px rgba(0,0,0,.4);position:relative}}
 .top{{font-size:12px;letter-spacing:3px;color:#8A6134}}
 h1{{font-size:31px;color:#6B3F1D;margin:8px 0 4px;letter-spacing:1px}}
 .sub{{font-size:14px;color:#8A6134;font-style:italic}}
 .line{{height:2px;background:#C8A96E;margin:16px 34px}}
 .info{{font-size:13px;color:#5A4630;line-height:2;text-align:left;padding:0 12px}}
 .net{{font-size:19px;font-weight:800;color:#6B3F1D;margin-top:12px}}
 .bar{{margin:16px auto 0;width:150px;height:42px;
      background:repeating-linear-gradient(90deg,#3A2A18 0 2px,transparent 2px 5px,#3A2A18 5px 6px,transparent 6px 10px)}}
 .code{{font-size:11px;color:#5A4630;letter-spacing:2px;margin-top:4px}}
 .synth{{position:absolute;bottom:5px;left:0;right:0;text-align:center;font-size:7.5px;color:#B9A98A}}
</style>
<div class="lbl">
  <div class="top">ĐẶC SẢN TÂY BẮC</div>
  <h1>MẮC KHÉN RỪNG</h1>
  <div class="sub">Hạt rừng Tây Bắc — nguyên chất</div>
  <div class="line"></div>
  <div class="info">
    Thành phần: 100% hạt mắc khén khô<br>
    HSD: 12 tháng kể từ ngày SX<br>
    NSX: 02/2026 &nbsp;·&nbsp; Lô: TB-2602<br>
    Bảo quản: nơi khô ráo, tránh nắng
  </div>
  <div class="net">KHỐI LƯỢNG TỊNH: 500g</div>
  <div class="bar"></div>
  <div class="code">8 93xxxx 00471 2</div>
  {MARK}
</div>
"""

SPECS = [("synthetic_receipt_R1.png", R1, 720, 960, 2),
         ("synthetic_receipt_R2.png", R2, 420, 820, 2),
         ("synthetic_label_R3.png",   R3, 640, 800, 2)]


async def main():
    async with async_playwright() as p:
        br = await p.chromium.launch(args=["--font-render-hinting=none"])
        for fn, html, w, h, s in SPECS:
            pg = await br.new_page(viewport={"width": w, "height": h}, device_scale_factor=s)
            await pg.set_content(html)
            await pg.wait_for_timeout(200)
            await pg.screenshot(path=str(OUT / fn))
            await pg.close()
            print("rendered", fn)
        await br.close()

    # R2: làm mờ + giảm tương phản + nhiễu, mô phỏng in nhiệt phai và chụp thiếu sáng
    p2 = OUT / "synthetic_receipt_R2.png"
    im = Image.open(p2).convert("RGB").rotate(-1.4, expand=True, fillcolor=(42, 42, 40))
    im = im.filter(ImageFilter.GaussianBlur(1.5))
    im = ImageEnhance.Contrast(im).enhance(0.62)
    im = ImageEnhance.Brightness(im).enhance(0.88)
    a = np.asarray(im).astype(np.int16) + np.random.normal(0, 7, np.asarray(im).shape).astype(np.int16)
    im = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))
    im.resize((int(im.width * .7), int(im.height * .7)), Image.LANCZOS) \
      .save(OUT / "synthetic_receipt_R2.jpg", "JPEG", quality=58)
    p2.unlink()
    print("degraded synthetic_receipt_R2.jpg")

    # R3: nghiêng nhẹ + mờ nhẹ, mô phỏng ảnh chụp vội bằng điện thoại
    p3 = OUT / "synthetic_label_R3.png"
    im = Image.open(p3).convert("RGB").rotate(2.6, expand=True,
                                              fillcolor=(110, 98, 87), resample=Image.BICUBIC)
    im = im.filter(ImageFilter.GaussianBlur(0.8))
    im.resize((int(im.width * .72), int(im.height * .72)), Image.LANCZOS) \
      .save(OUT / "synthetic_label_R3.jpg", "JPEG", quality=76)
    p3.unlink()
    print("degraded synthetic_label_R3.jpg")

asyncio.run(main())
