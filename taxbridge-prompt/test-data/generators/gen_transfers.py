#!/usr/bin/env python3
"""
Sinh ảnh chuyển khoản SYNTHETIC cho bộ test TaxBridge.

Layout mô phỏng cấu trúc màn hình "chuyển khoản thành công" của app ngân hàng VN
(theo ảnh mẫu Binh cung cấp), nhưng dùng thương hiệu ngân hàng HƯ CẤU và có dấu
synthetic rõ ràng — để fixture không bao giờ dùng được như bằng chứng thanh toán thật.
Các field mà AI phải trích xuất (số tiền, lời nhắn, tên, thời gian, mã GD) giữ
nguyên format thực tế.
"""
import asyncio, json, pathlib
from playwright.async_api import async_playwright

OUT = pathlib.Path("/home/claude/tb/out/evidence")
OUT.mkdir(parents=True, exist_ok=True)

FONT = "'Liberation Sans', 'DejaVu Sans', sans-serif"

STATUS_BAR = """
<div class="sb">
  <div class="sb-t">{time}</div>
  <div class="sb-i">
    <svg width="18" height="12" viewBox="0 0 18 12"><rect x="0" y="8" width="3" height="4" rx="1"/><rect x="5" y="5.5" width="3" height="6.5" rx="1"/><rect x="10" y="3" width="3" height="9" rx="1" opacity=".35"/><rect x="15" y="0" width="3" height="12" rx="1" opacity=".35"/></svg>
    <svg width="16" height="12" viewBox="0 0 16 12"><path d="M8 10.5 5.6 8.1a3.4 3.4 0 0 1 4.8 0zM8 6.2c-1.6 0-3 .6-4.1 1.7L2.4 6.4A8 8 0 0 1 8 4.1a8 8 0 0 1 5.6 2.3l-1.5 1.5A5.8 5.8 0 0 0 8 6.2zM8 2.1c-2.7 0-5.2 1-7 2.8L-.4 3.5A11.9 11.9 0 0 1 8 0c3.3 0 6.3 1.3 8.4 3.5L15 4.9A9.9 9.9 0 0 0 8 2.1z"/></svg>
    <svg width="26" height="12" viewBox="0 0 26 12"><rect x="0.5" y="0.5" width="22" height="11" rx="3" fill="none" stroke="currentColor" opacity=".45"/><rect x="2" y="2" width="17" height="8" rx="1.6"/><path d="M24 4.2v3.6a2 2 0 0 0 0-3.6z" opacity=".45"/></svg>
  </div>
</div>
"""

SYNTH_MARK = '<div class="synth">DỮ LIỆU THỬ NGHIỆM — SYNTHETIC TEST FIXTURE — KHÔNG PHẢI GIAO DỊCH THẬT</div>'


def variant_a(c):
    """Kiểu 'cream + coins': gần nhất với ảnh mẫu."""
    return f"""
<style>
 *{{margin:0;padding:0;box-sizing:border-box;-webkit-font-smoothing:antialiased}}
 body{{width:390px;height:844px;font-family:{FONT};background:#FAF7EF;position:relative;overflow:hidden;color:#111}}
 body:before{{content:'';position:absolute;inset:-40% -10% auto -10%;height:150%;
   background:repeating-radial-gradient(circle at 30% 18%, rgba(0,0,0,.035) 0 1px, transparent 1px 9px);}}
 .coin{{position:absolute;border-radius:50%}}
 .c1{{width:22px;height:22px;top:96px;left:112px;background:radial-gradient(circle at 35% 30%,#FFEFB8,#EFC451)}}
 .c2{{width:15px;height:15px;top:140px;right:96px;background:radial-gradient(circle at 35% 30%,#FFEFB8,#EFC451)}}
 .c3{{width:26px;height:26px;top:190px;right:38px;background:radial-gradient(circle at 35% 30%,#FFEFB8,#EFC451)}}
 .c4{{width:17px;height:17px;top:255px;left:58px;background:radial-gradient(circle at 35% 30%,#FFEFB8,#EFC451);opacity:.75}}
 .sb{{position:relative;display:flex;justify-content:space-between;align-items:center;padding:13px 22px 0;font-size:15px;font-weight:700}}
 .sb-i{{display:flex;gap:5px;align-items:center;fill:#111;color:#111}}
 .wrap{{position:relative;padding:0 24px}}
 .share{{display:flex;justify-content:flex-end;margin-top:18px}}
 .check{{width:66px;height:66px;border-radius:50%;background:#12C06A;display:flex;align-items:center;justify-content:center;margin-top:44px}}
 .brand{{display:flex;align-items:center;gap:8px;margin-top:46px}}
 .brand .nm{{font-size:15px;font-weight:800;letter-spacing:.4px;color:#1B3B6F}}
 .brand .mk{{width:17px;height:17px;background:#C8102E;transform:rotate(45deg);border-radius:2px}}
 h1{{font-size:29px;line-height:1.22;font-weight:700;margin-top:12px;letter-spacing:-.4px}}
 .sec{{margin-top:30px}}
 .lb{{font-size:14.5px;color:#8A8A8E;margin-bottom:5px}}
 .vl{{font-size:16.5px;line-height:1.35}}
 .btns{{position:absolute;left:24px;right:24px;bottom:48px}}
 .b1{{background:#0E0E0E;color:#fff;border-radius:28px;height:53px;display:flex;align-items:center;justify-content:center;font-size:16.5px;font-weight:600}}
 .b2{{margin-top:11px;border:1.4px solid #0E0E0E;border-radius:28px;height:53px;display:flex;align-items:center;justify-content:center;font-size:16.5px;font-weight:600}}
 .synth{{position:absolute;bottom:24px;left:0;right:0;text-align:center;font-size:8.5px;color:#B9B2A2;letter-spacing:.3px}}
 .bar{{position:absolute;bottom:9px;left:50%;transform:translateX(-50%);width:134px;height:5px;background:#111;border-radius:3px;opacity:.85}}
</style>
<div class="coin c1"></div><div class="coin c2"></div><div class="coin c3"></div><div class="coin c4"></div>
{STATUS_BAR.format(time=c['clock'])}
<div class="wrap">
  <div class="share"><svg width="19" height="23" viewBox="0 0 19 23" fill="none" stroke="#111" stroke-width="1.7"><path d="M9.5 1.5v13M5 5.5 9.5 1l4.5 4.5M2 10.5v10h15v-10"/></svg></div>
  <div class="check"><svg width="32" height="24" viewBox="0 0 32 24" fill="none" stroke="#fff" stroke-width="3.4" stroke-linecap="round" stroke-linejoin="round"><path d="M3 12.5 11.5 21 29 3.5"/></svg></div>
  <div class="brand"><div class="nm">{c['bank_brand']}</div><div class="mk"></div></div>
  <h1>Chuyển thành công<br>tới {c['to_name']}<br>{c['amount_text']}</h1>
  <div class="sec"><div class="lb">Thông tin chi tiết</div>
    <div class="vl">{c['dest_bank']}<br>{c['dest_acct']}</div></div>
  <div class="sec"><div class="lb">Lời nhắn</div><div class="vl">{c['memo']}</div></div>
  <div class="sec"><div class="lb">Ngày thực hiện</div><div class="vl">{c['date_text']}</div></div>
  <div class="sec"><div class="lb">Mã giao dịch</div><div class="vl">{c['ftid']}</div></div>
</div>
<div class="btns"><div class="b1">Hoàn thành</div><div class="b2">Thực hiện giao dịch khác</div></div>
<div class="bar"></div>
{SYNTH_MARK}
"""


def variant_b(c):
    """Kiểu 'header xanh + card trắng'."""
    return f"""
<style>
 *{{margin:0;padding:0;box-sizing:border-box;-webkit-font-smoothing:antialiased}}
 body{{width:390px;height:844px;font-family:{FONT};background:#EEF2F7;position:relative;overflow:hidden;color:#15203A}}
 .hd{{background:linear-gradient(160deg,#1A4FA0,#2C7BD4);color:#fff;padding-bottom:40px;border-radius:0 0 26px 26px}}
 .sb{{display:flex;justify-content:space-between;align-items:center;padding:13px 22px 0;font-size:15px;font-weight:700;color:#fff}}
 .sb-i{{display:flex;gap:5px;align-items:center;fill:#fff;color:#fff}}
 .bk{{text-align:center;font-size:13px;font-weight:700;letter-spacing:1.6px;margin-top:16px;opacity:.9}}
 .ck{{width:58px;height:58px;border-radius:50%;background:rgba(255,255,255,.18);border:2px solid rgba(255,255,255,.85);
     display:flex;align-items:center;justify-content:center;margin:26px auto 0}}
 .st{{text-align:center;font-size:16px;margin-top:16px;opacity:.95}}
 .am{{text-align:center;font-size:33px;font-weight:700;margin-top:7px;letter-spacing:-.5px}}
 .card{{margin:-24px 18px 0;background:#fff;border-radius:18px;padding:6px 18px;box-shadow:0 6px 22px rgba(20,40,80,.10)}}
 .row{{display:flex;justify-content:space-between;gap:14px;padding:14px 0;border-bottom:1px solid #EFF1F5;font-size:14.5px}}
 .row:last-child{{border-bottom:none}}
 .k{{color:#8590A6;flex:0 0 41%}}
 .v{{text-align:right;font-weight:600;line-height:1.4;color:#15203A}}
 .b1{{position:absolute;left:18px;right:18px;bottom:52px;background:#1A4FA0;color:#fff;border-radius:14px;height:52px;
     display:flex;align-items:center;justify-content:center;font-size:16.5px;font-weight:700}}
 .synth{{position:absolute;bottom:7px;left:0;right:0;text-align:center;font-size:8.5px;color:#A9B4C6}}
 .bar{{position:absolute;bottom:22px;left:50%;transform:translateX(-50%);width:134px;height:5px;background:#3A4A66;border-radius:3px;opacity:.55}}
</style>
<div class="hd">
  {STATUS_BAR.format(time=c['clock'])}
  <div class="bk">{c['bank_brand']}</div>
  <div class="ck"><svg width="28" height="21" viewBox="0 0 32 24" fill="none" stroke="#fff" stroke-width="3.6" stroke-linecap="round" stroke-linejoin="round"><path d="M3 12.5 11.5 21 29 3.5"/></svg></div>
  <div class="st">Giao dịch thành công</div>
  <div class="am">{c['amount_text']}</div>
</div>
<div class="card">
  <div class="row"><div class="k">Người nhận</div><div class="v">{c['to_name']}</div></div>
  <div class="row"><div class="k">Ngân hàng</div><div class="v">{c['dest_bank']}</div></div>
  <div class="row"><div class="k">Số tài khoản</div><div class="v">{c['dest_acct']}</div></div>
  <div class="row"><div class="k">Nội dung</div><div class="v">{c['memo']}</div></div>
  <div class="row"><div class="k">Thời gian</div><div class="v">{c['date_text']}</div></div>
  <div class="row"><div class="k">Mã giao dịch</div><div class="v">{c['ftid']}</div></div>
</div>
<div class="b1">Hoàn thành</div>
<div class="bar"></div>
{SYNTH_MARK}
"""


def variant_c(c):
    """Kiểu 'dark minimal'."""
    return f"""
<style>
 *{{margin:0;padding:0;box-sizing:border-box;-webkit-font-smoothing:antialiased}}
 body{{width:390px;height:844px;font-family:{FONT};background:#10131A;color:#F2F4F8;position:relative;overflow:hidden}}
 .sb{{display:flex;justify-content:space-between;align-items:center;padding:13px 22px 0;font-size:15px;font-weight:700}}
 .sb-i{{display:flex;gap:5px;align-items:center;fill:#F2F4F8;color:#F2F4F8}}
 .ck{{width:74px;height:74px;border-radius:50%;background:rgba(28,214,139,.13);border:2px solid #1CD68B;
     display:flex;align-items:center;justify-content:center;margin:62px auto 0}}
 .st{{text-align:center;font-size:17px;margin-top:22px;color:#9AA4B6}}
 .am{{text-align:center;font-size:36px;font-weight:700;margin-top:8px;letter-spacing:-.6px}}
 .brandline{{text-align:center;font-size:12px;letter-spacing:2.2px;color:#6D788C;margin-top:14px}}
 .list{{margin:40px 22px 0}}
 .row{{display:flex;justify-content:space-between;gap:14px;padding:15px 0;border-bottom:1px solid #1E2430;font-size:14.5px}}
 .k{{color:#6D788C;flex:0 0 40%}}
 .v{{text-align:right;line-height:1.4;font-weight:600}}
 .b1{{position:absolute;left:22px;right:22px;bottom:50px;background:#1CD68B;color:#06251A;border-radius:15px;height:53px;
     display:flex;align-items:center;justify-content:center;font-size:16.5px;font-weight:700}}
 .synth{{position:absolute;bottom:7px;left:0;right:0;text-align:center;font-size:8.5px;color:#39404F}}
 .bar{{position:absolute;bottom:22px;left:50%;transform:translateX(-50%);width:134px;height:5px;background:#8E97A8;border-radius:3px;opacity:.5}}
</style>
{STATUS_BAR.format(time=c['clock'])}
<div class="ck"><svg width="34" height="26" viewBox="0 0 32 24" fill="none" stroke="#1CD68B" stroke-width="3.4" stroke-linecap="round" stroke-linejoin="round"><path d="M3 12.5 11.5 21 29 3.5"/></svg></div>
<div class="st">Chuyển tiền thành công</div>
<div class="am">{c['amount_text']}</div>
<div class="brandline">{c['bank_brand']}</div>
<div class="list">
  <div class="row"><div class="k">Đến</div><div class="v">{c['to_name']}</div></div>
  <div class="row"><div class="k">Tại</div><div class="v">{c['dest_bank']}</div></div>
  <div class="row"><div class="k">Tài khoản</div><div class="v">{c['dest_acct']}</div></div>
  <div class="row"><div class="k">Lời nhắn</div><div class="v">{c['memo']}</div></div>
  <div class="row"><div class="k">Thời gian</div><div class="v">{c['date_text']}</div></div>
  <div class="row"><div class="k">Mã GD</div><div class="v">{c['ftid']}</div></div>
</div>
<div class="b1">Xong</div>
<div class="bar"></div>
{SYNTH_MARK}
"""


def variant_d(c):
    """Kiểu 'biến động số dư / thông báo tiền vào' — chụp từ máy CHỦ SHOP."""
    return f"""
<style>
 *{{margin:0;padding:0;box-sizing:border-box;-webkit-font-smoothing:antialiased}}
 body{{width:390px;height:844px;font-family:{FONT};background:#F4F6F8;color:#15203A;position:relative;overflow:hidden}}
 .sb{{display:flex;justify-content:space-between;align-items:center;padding:13px 22px 0;font-size:15px;font-weight:700}}
 .sb-i{{display:flex;gap:5px;align-items:center;fill:#15203A;color:#15203A}}
 .nav{{display:flex;align-items:center;gap:12px;padding:20px 20px 16px;font-size:17px;font-weight:700}}
 .card{{margin:4px 16px 0;background:#fff;border-radius:16px;padding:22px 18px;box-shadow:0 3px 14px rgba(20,40,80,.07)}}
 .tag{{display:inline-block;background:#E4F7EE;color:#0E9A5F;font-size:12px;font-weight:700;padding:5px 11px;border-radius:20px}}
 .am{{font-size:31px;font-weight:700;color:#0E9A5F;margin-top:13px;letter-spacing:-.5px}}
 .sub{{font-size:13.5px;color:#8590A6;margin-top:5px}}
 .hr{{height:1px;background:#EFF1F5;margin:18px 0}}
 .row{{display:flex;justify-content:space-between;gap:14px;padding:9px 0;font-size:14.5px}}
 .k{{color:#8590A6;flex:0 0 38%}}
 .v{{text-align:right;font-weight:600;line-height:1.4}}
 .bal{{margin:14px 16px 0;background:#fff;border-radius:16px;padding:16px 18px;font-size:14px;color:#8590A6;
      display:flex;justify-content:space-between;box-shadow:0 3px 14px rgba(20,40,80,.07)}}
 .bal b{{color:#15203A;font-size:15px}}
 .synth{{position:absolute;bottom:7px;left:0;right:0;text-align:center;font-size:8.5px;color:#A9B4C6}}
 .bar{{position:absolute;bottom:22px;left:50%;transform:translateX(-50%);width:134px;height:5px;background:#3A4A66;border-radius:3px;opacity:.5}}
</style>
{STATUS_BAR.format(time=c['clock'])}
<div class="nav"><svg width="11" height="18" viewBox="0 0 11 18" fill="none" stroke="#15203A" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M9.5 1.5 2 9l7.5 7.5"/></svg> Chi tiết giao dịch</div>
<div class="card">
  <div class="tag">TIỀN VÀO</div>
  <div class="am">{c['amount_text']}</div>
  <div class="sub">{c['bank_brand']} · Tài khoản {c['dest_acct']}</div>
  <div class="hr"></div>
  <div class="row"><div class="k">Người chuyển</div><div class="v">{c['to_name']}</div></div>
  <div class="row"><div class="k">Ngân hàng gửi</div><div class="v">{c['dest_bank']}</div></div>
  <div class="row"><div class="k">Nội dung</div><div class="v">{c['memo']}</div></div>
  <div class="row"><div class="k">Thời gian</div><div class="v">{c['date_text']}</div></div>
  <div class="row"><div class="k">Mã giao dịch</div><div class="v">{c['ftid']}</div></div>
</div>
<div class="bal"><span>Số dư khả dụng</span><b>{c.get('balance','—')}</b></div>
<div class="bar"></div>
{SYNTH_MARK}
"""


VARIANTS = {"A": variant_a, "B": variant_b, "C": variant_c, "D": variant_d}

CASES = json.loads(pathlib.Path("/home/claude/tb/transfer_cases.json").read_text())


async def main():
    async with async_playwright() as p:
        br = await p.chromium.launch(args=["--font-render-hinting=none"])
        for c in CASES:
            pg = await br.new_page(viewport={"width": 390, "height": 844},
                                   device_scale_factor=c.get("scale", 2))
            await pg.set_content(VARIANTS[c["variant"]](c))
            await pg.wait_for_timeout(220)
            out = OUT / c["file"]
            await pg.screenshot(path=str(out), type="png")
            await pg.close()
            print("rendered", out.name)
        await br.close()

asyncio.run(main())
