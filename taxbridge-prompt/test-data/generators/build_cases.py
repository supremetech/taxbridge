#!/usr/bin/env python3
"""
Build bộ eval TaxBridge: 21 case + ground truth + manifest.

Số liệu tổng hợp cuối ngày (case D1) được TÍNH TỪ chính các case, không gõ tay,
kèm assert nội bộ — nên ground truth không thể lệch khỏi dữ liệu.
"""
import json, pathlib, sys

ROOT = pathlib.Path("/home/claude/tb/out")
CASES = ROOT / "cases"; CASES.mkdir(parents=True, exist_ok=True)

DATE = "2026-09-11"
TZ = "+07:00"
SHOP = "Hộ kinh doanh Đặc sản Tây Bắc Hương Núi"
OWNER = "DINH QUOC BAO"   # tên chủ shop — hiện trên MỌI ảnh chuyển khoản khách gửi


def ts(hhmm): return f"{DATE}T{hhmm}:00{TZ}"


# ─────────────────────────────────────────────────────────────────────────────
# EVENTS: text + audio + receipt
# ─────────────────────────────────────────────────────────────────────────────
EVENTS = [
    dict(id="T1", ct="TEXT", tag="CLEAN_SALE", at="08:20",
         input_text="Bán chị Lan 2 hộp thịt trâu gác bếp 900 nghìn, chị ấy chuyển khoản sau",
         exp=dict(type="SALE", amount=900_000, description="Bán 2 hộp thịt trâu gác bếp",
                  counterparty="chị Lan", paymentMethod="BANK", paymentStatus="UNPAID"),
         final_status="CONFIRMED",
         notes="Baseline text. Mọi field phải đúng 100%. 'chuyển khoản sau' ⇒ UNPAID, không phải PAID."),

    dict(id="T2", ct="TEXT", tag="MISSING_PAYMENT_METHOD", at="09:05",
         input_text="Khách lẻ mua 1 cân măng rối với 1 cân chè dây, 470 nghìn",
         exp=dict(type="SALE", amount=470_000, description="Bán 1kg măng rối và 1kg chè dây",
                  counterparty=None, paymentMethod="UNKNOWN", paymentStatus="UNKNOWN"),
         final_status="CONFIRMED",
         notes="BẪY: không nói hình thức thanh toán. AI phải trả UNKNOWN, "
               "tuyệt đối không mặc định CASH chỉ vì là khách lẻ."),

    dict(id="T3", ct="TEXT", tag="CLEAN_PURCHASE", at="07:30",
         input_text="Mua thùng carton với băng dính đóng hàng hết 220 nghìn, trả tiền mặt",
         exp=dict(type="PURCHASE", amount=220_000, description="Mua thùng carton và băng dính đóng hàng",
                  counterparty=None, paymentMethod="CASH", paymentStatus="PAID"),
         final_status="CONFIRMED", notes="Baseline chi phí."),

    dict(id="T4", ct="TEXT", tag="OWNER_MONEY_TEXT", at="07:45",
         input_text="Sáng nay tôi bỏ thêm 500 nghìn tiền túi vào quỹ để có tiền lẻ trả khách",
         exp=dict(type="OWNER_MONEY", amount=500_000, description="Chủ hộ bỏ thêm tiền vào quỹ",
                  counterparty=None, paymentMethod="CASH", paymentStatus="PAID"),
         final_status="CONFIRMED",
         notes="HERO: tiền vào quỹ nhưng KHÔNG phải doanh thu. Nếu ra SALE là sai nghiêm trọng."),

    dict(id="T5", ct="TEXT", tag="AMBIGUOUS_PAIR_A", at="12:50",
         input_text="Chị Hà đặt 2 cân macca 600 nghìn, chuyển khoản sau",
         exp=dict(type="SALE", amount=600_000, description="Bán 2kg hạt macca",
                  counterparty="chị Hà", paymentMethod="BANK", paymentStatus="UNPAID"),
         final_status="CONFIRMED",
         notes="Cùng số tiền 600.000 với A3 — tạo tình huống nhập nhằng cho M3."),

    dict(id="T6", ct="TEXT", tag="COLLOQUIAL_AMOUNT", at="13:05",
         input_text="Anh Dũng lấy 1 set quà tặng Tết 1 triệu 250, chuyển khoản",
         exp=dict(type="SALE", amount=1_250_000, description="Bán 1 set quà tặng Tết",
                  counterparty="anh Dũng", paymentMethod="BANK", paymentStatus="UNPAID"),
         final_status="CONFIRMED",
         notes="BẪY số tiền khẩu ngữ: '1 triệu 250' = 1.250.000, không phải 1.250 hay 250.000."),

    dict(id="A1", ct="AUDIO", tag="CLEAN_SALE_VOICE", at="09:40",
         evidence="synthetic_voice_A1.m4a",
         transcript="Bán cho anh Minh ba hộp tỏi đen cô đơn, bảy trăm hai mươi nghìn, "
                    "anh ấy trả tiền mặt luôn rồi.",
         exp=dict(type="SALE", amount=720_000, description="Bán 3 hộp tỏi đen cô đơn",
                  counterparty="anh Minh", paymentMethod="CASH", paymentStatus="PAID"),
         final_status="CONFIRMED", notes="Baseline giọng nói, phòng yên tĩnh."),

    dict(id="A2", ct="AUDIO", tag="DIALECT_PLUS_NOISE", at="10:30",
         evidence="synthetic_voice_A2.m4a",
         transcript="Bán cho o Hương một cân mắc khén, bốn trăm nghìn, o nớ nói chút nữa chuyển khoản.",
         exp=dict(type="SALE", amount=400_000, description="Bán 1kg mắc khén",
                  counterparty="Hương", paymentMethod="BANK", paymentStatus="UNPAID"),
         final_status="CONFIRMED",
         notes="Giọng miền Trung + ồn nền (SNR 12dB). Từ địa phương 'o' = 'cô', "
               "'o nớ' = 'cô ấy'. counterparty đúng là Hương."),

    dict(id="A3", ct="AUDIO", tag="CORRECTION_IN_SPEECH", at="11:15",
         evidence="synthetic_voice_A3.m4a",
         transcript="Chị Thu lấy hai hộp trà ô long... à không, ba hộp, tổng sáu trăm nghìn, "
                    "chị ấy chuyển khoản sau.",
         exp=dict(type="SALE", amount=600_000, description="Bán 3 hộp trà ô long",
                  counterparty="chị Thu", paymentMethod="BANK", paymentStatus="UNPAID"),
         final_status="CONFIRMED",
         notes="BẪY tự sửa giữa câu: phải lấy SỐ CHỐT CUỐI (3 hộp / 600.000), "
               "không phải 'hai hộp' nghe đầu tiên."),

    dict(id="A4", ct="AUDIO", tag="NO_BUSINESS_INTENT", at="12:10",
         evidence="synthetic_voice_A4.m4a",
         transcript="Ừ trưa nay ăn cơm chỗ cũ đi, tầm mười một giờ rưỡi nhé, để tí nữa tính.",
         exp=None, expect_no_event=True,
         notes="BẪY: không có nghiệp vụ nào. Kỳ vọng type=UNKNOWN + confidence thấp, "
               "hoặc capture FAILED — KHÔNG được bịa ra giao dịch. "
               "Câu có chứa số ('mười một giờ rưỡi') để bẫy việc bắt nhầm thành số tiền."),

    dict(id="R1", ct="IMAGE_RECEIPT", tag="CLEAN_RECEIPT", at="14:10",
         evidence="synthetic_receipt_R1.png",
         exp=dict(type="PURCHASE", amount=1_500_000, description="Nhập 5kg hạt điều",
                  counterparty="Cơ sở chế biến hạt điều Bình Phước",
                  paymentMethod="BANK", paymentStatus="PAID"),
         final_status="CONFIRMED",
         notes="Hóa đơn in rõ. Phải lấy TỔNG CỘNG 1.500.000, không lấy dòng lẻ 1.200.000."),

    dict(id="R2", ct="IMAGE_RECEIPT", tag="LOW_QUALITY_RECEIPT", at="14:25",
         evidence="synthetic_receipt_R2.jpg",
         exp=dict(type="PURCHASE", amount=185_000, description="Mua túi zip, tem nhãn, băng dính, túi giấy",
                  counterparty="Cửa hàng bao bì Minh Long",
                  paymentMethod="CASH", paymentStatus="PAID"),
         final_status="DRAFT",
         notes="Hóa đơn nhiệt in mờ, ảnh chụp thiếu sáng. BẪY: trên phiếu có 200.000 (tiền "
               "khách đưa) và 15.000 (tiền thối) — phải lấy TỔNG CỘNG 185.000. "
               "Kỳ vọng confidence giảm rõ so với R1. Case này CỐ Ý để nguyên DRAFT "
               "để sinh warning DRAFT_EVENT ở D1."),

    dict(id="R3", ct="IMAGE_RECEIPT", tag="IMAGE_UNCLASSIFIED", at="15:05",
         evidence="synthetic_label_R3.jpg",
         exp=None, expect_no_event=True,
         notes="Ảnh nhãn sản phẩm, không phải chứng từ. Kỳ vọng KHÔNG tạo event; "
               "nếu đến từ Zalo thì phân loại IMAGE_UNKNOWN. "
               "BẪY: ảnh có số '500g' và '8 93xxxx 00471 2' — không được biến thành số tiền."),
]

# ─────────────────────────────────────────────────────────────────────────────
# MONEY MOVEMENTS — 7 ảnh chuyển khoản
# shot_type: "customer_outgoing" = khách chụp màn hình chuyển đi rồi gửi cho chủ shop
#            (hành vi phổ biến nhất ở hộ kinh doanh VN — tên trên màn hình là CHỦ SHOP)
#            "shop_incoming"     = chủ shop chụp thông báo biến động số dư
# ─────────────────────────────────────────────────────────────────────────────
MOVES = [
    dict(id="M1", tag="CLEAN_MATCH", at="10:05", evidence="synthetic_transfer_M1.png",
         shot_type="customer_outgoing", amount=900_000, memo="LAN 2HOP TRAU GAC BEP",
         screen_name=OWNER, exp_counterparty="Lan", cp_source="memo",
         exp_status="MATCHED", match_to="T1", candidates=["T1"], auto_match_ok=True,
         notes="Khớp sạch: đúng số tiền + memo có tên khách. Top-1 candidate phải là T1. "
               "BẪY TÊN: tên trên màn hình là DINH QUOC BAO (chủ shop) — "
               "counterparty đúng là 'Lan' lấy từ memo, KHÔNG phải chủ shop."),

    dict(id="M2", tag="MATCH_BY_AMOUNT_ONLY", at="11:40", evidence="synthetic_transfer_M2.jpg",
         shot_type="customer_outgoing", amount=400_000, memo="CK HUONG MK",
         screen_name=OWNER, exp_counterparty="Hương", cp_source="memo",
         exp_status="MATCHED", match_to="A2", candidates=["A2"], auto_match_ok=True,
         notes="Memo viết tắt khó hiểu ('MK' = mắc khén) + ảnh đã bị nén qua Zalo. "
               "Vẫn phải ra đúng candidate nhờ số tiền trùng tuyệt đối."),

    dict(id="M3", tag="AMBIGUOUS_CANDIDATES", at="13:20", evidence="synthetic_transfer_M3.png",
         shot_type="customer_outgoing", amount=600_000, memo="CHUYEN TIEN",
         screen_name=OWNER, exp_counterparty=None, cp_source="none",
         exp_status="MATCHED", match_to="A3", candidates=["A3", "T5"], auto_match_ok=False,
         notes="HERO: memo vô nghĩa, 600.000 khớp CẢ A3 (chị Thu) và T5 (chị Hà). "
               "Kỳ vọng trả về ĐỦ 2 candidate và KHÔNG tự ghép. "
               "Trạng thái cuối giả định user chọn A3."),

    dict(id="M4", tag="UNMATCHED_TO_DEPOSIT", at="14:45", evidence="synthetic_transfer_M4.png",
         shot_type="customer_outgoing", amount=380_000, memo="COC MINH DAT HANG TET",
         screen_name=OWNER, exp_counterparty="Minh", cp_source="memo",
         exp_status="CLASSIFIED", classify="DEPOSIT", candidates=[], auto_match_ok=False,
         notes="HERO: không khớp đơn nào, memo có 'COC' ⇒ đặt cọc. "
               "Sau khi classify DEPOSIT, doanh thu PHẢI không đổi."),

    dict(id="M5", tag="UNMATCHED_NO_HINT", at="15:30", evidence="synthetic_transfer_M5.jpg",
         shot_type="customer_outgoing", amount=250_000, memo="ck",
         screen_name=OWNER, exp_counterparty=None, cp_source="none",
         exp_status="CLASSIFIED", classify="OTHER", candidates=[], auto_match_ok=False,
         notes="Memo rỗng nghĩa, ảnh độ phân giải thấp + nén nặng. Không có candidate hợp lý. "
               "Kỳ vọng trả candidates=[] và chờ user; AI không được đoán bừa."),

    dict(id="M6", tag="UNMATCHED_TO_OWNER", at="16:20", evidence="synthetic_transfer_M6.png",
         shot_type="customer_outgoing", amount=5_000_000, memo="CHUYEN QUY BAN HANG",
         screen_name=OWNER, exp_counterparty=None, cp_source="none",
         exp_status="CLASSIFIED", classify="OWNER_MONEY", candidates=[], auto_match_ok=False,
         notes="HERO: chủ hộ tự chuyển từ tài khoản cá nhân sang tài khoản bán hàng. "
               "Số tiền lớn (5tr) rất dễ bị nhầm thành doanh thu — phải là OWNER_MONEY."),

    dict(id="M7", tag="AMOUNT_MISMATCH_FEE", at="17:10", evidence="synthetic_transfer_M7.png",
         shot_type="shop_incoming", amount=1_242_000, memo="DUNG THANH TOAN DON QUA TANG",
         screen_name="HOANG VAN DUNG", exp_counterparty="HOANG VAN DUNG", cp_source="screen",
         exp_status="UNMATCHED", candidates=[], auto_match_ok=False,
         notes="Ảnh kiểu biến động số dư (chụp từ máy CHỦ SHOP) — ở đây tên trên màn hình "
               "ĐÚNG là khách. Số tiền 1.242.000 lệch 8.000 so với đơn T6 (1.250.000) do phí CK. "
               "Kỳ vọng KHÔNG tự ghép (amount không khớp tuyệt đối) ⇒ để lại warning cuối ngày."),
]

# ─────────────────────────────────────────────────────────────────────────────
# Tính D1 từ dữ liệu trên
# ─────────────────────────────────────────────────────────────────────────────
ev = {e["id"]: e for e in EVENTS}
paid_by_match = {m["match_to"] for m in MOVES if m.get("match_to")}

revenue = sum(e["exp"]["amount"] for e in EVENTS
              if e["exp"] and e["exp"]["type"] == "SALE" and e["final_status"] == "CONFIRMED")
expense = sum(e["exp"]["amount"] for e in EVENTS
              if e["exp"] and e["exp"]["type"] == "PURCHASE" and e["final_status"] == "CONFIRMED")
collected = sum(
    e["exp"]["amount"] for e in EVENTS
    if e["exp"] and e["exp"]["type"] == "SALE" and e["final_status"] == "CONFIRMED"
    and (e["exp"]["paymentStatus"] == "PAID" or e["id"] in paid_by_match))
receivable = revenue - collected

non_revenue_inflow = (
    sum(m["amount"] for m in MOVES if m.get("classify") in ("DEPOSIT", "OWNER_MONEY", "OTHER"))
    + sum(e["exp"]["amount"] for e in EVENTS
          if e["exp"] and e["exp"]["type"] == "OWNER_MONEY"))

warnings = []
for m in MOVES:
    if m["exp_status"] == "UNMATCHED":
        warnings.append(dict(warningId=f"UNMATCHED_MONEY:{m['id']}", type="UNMATCHED_MONEY",
                             status="OPEN", resourceType="MONEY_MOVEMENT", resourceId=m["id"],
                             amount=m["amount"]))
for e in EVENTS:
    if e["exp"] and e["final_status"] == "DRAFT":
        warnings.append(dict(warningId=f"DRAFT_EVENT:{e['id']}", type="DRAFT_EVENT",
                             status="OPEN", resourceType="EVENT", resourceId=e["id"],
                             amount=e["exp"]["amount"]))

# assert nội bộ — sai là dừng, không xuất bộ dữ liệu lệch
assert revenue == 4_940_000, revenue
assert collected + receivable == revenue
assert all(m["match_to"] in ev for m in MOVES if m.get("match_to"))
for m in MOVES:
    for c in m["candidates"]:
        assert ev[c]["exp"]["amount"] == m["amount"], f"{m['id']} candidate {c} lệch số tiền"
        assert ev[c]["exp"]["paymentStatus"] == "UNPAID", f"{m['id']} candidate {c} không UNPAID"

# ─────────────────────────────────────────────────────────────────────────────
# Ghi file
# ─────────────────────────────────────────────────────────────────────────────
CRIT_EVENT = ["type", "amount", "paymentMethod", "paymentStatus"]
CRIT_MOVE = ["direction", "amount", "status", "classificationType"]
SOFT = ["description", "counterparty"]

for e in EVENTS:
    doc = {
        "caseId": e["id"], "captureType": e["ct"], "scenarioTag": e["tag"],
        "occurredAt": ts(e["at"]),
        "input": ({"text": e["input_text"]} if e.get("input_text")
                  else {"evidenceFile": f"evidence/{e['evidence']}",
                        "referenceTranscript": e.get("transcript")}),
        "expectedOutput": (None if e.get("expect_no_event") else
                           {**e["exp"], "occurredAt": ts(e["at"])}),
        "expectNoEvent": bool(e.get("expect_no_event")),
        "expectedFinalStatus": e.get("final_status"),
        "criticalFields": [] if e.get("expect_no_event") else CRIT_EVENT,
        "softFields_gradedByHuman": [] if e.get("expect_no_event") else SOFT,
        "tolerance": {
            "amount": "exact",
            "occurredAt": "±5 phút; nếu input không nêu giờ thì lấy thời điểm tạo capture",
            "description": "human — chấp nhận diễn đạt khác nếu đúng ý",
            "counterparty": "human — chấp nhận thiếu/thừa tiền tố (chị/anh/o)",
        },
        "notes": e["notes"],
    }
    (CASES / f"{e['id']}.json").write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n")

for m in MOVES:
    doc = {
        "caseId": m["id"], "captureType": "IMAGE_TRANSFER", "scenarioTag": m["tag"],
        "occurredAt": ts(m["at"]),
        "input": {"evidenceFile": f"evidence/{m['evidence']}",
                  "screenshotType": m["shot_type"],
                  "nameVisibleOnScreen": m["screen_name"],
                  "memoOnScreen": m["memo"]},
        "expectedOutput": {
            "direction": "IN", "amount": m["amount"], "memo": m["memo"],
            "counterparty": m["exp_counterparty"],
            "occurredAt": ts(m["at"]),
            "status": "UNMATCHED",
        },
        "counterpartyTrap": {
            "expectedSource": m["cp_source"],
            "mustNotReturn": OWNER if m["shot_type"] == "customer_outgoing" else None,
            "why": ("Ảnh do khách chụp màn hình chuyển đi nên tên hiển thị là chủ shop; "
                    "counterparty phải suy từ memo, hoặc để trống nếu memo không có tên."
                    if m["shot_type"] == "customer_outgoing"
                    else "Ảnh biến động số dư chụp từ máy chủ shop — tên hiển thị đúng là khách."),
        },
        "expectedMatching": {
            "expectedCandidateEventIds": m["candidates"],
            "autoMatchAllowed": m["auto_match_ok"],
            "expectedTop1": m["candidates"][0] if (m["auto_match_ok"] and m["candidates"]) else None,
        },
        "expectedUserAction": (
            {"action": "match", "toEventId": m["match_to"]} if m.get("match_to")
            else {"action": "classify", "type": m.get("classify")} if m.get("classify")
            else {"action": "none", "leftAs": "UNMATCHED"}),
        "expectedFinalStatus": m["exp_status"],
        "effectOnRevenue": "no_change" if m.get("classify") else (
            "collected_increases" if m.get("match_to") else "no_change"),
        "criticalFields": CRIT_MOVE,
        "softFields_gradedByHuman": ["counterparty", "memo"],
        "tolerance": {"amount": "exact", "memo": "human — chấp nhận sai khác hoa/thường",
                      "occurredAt": "±5 phút"},
        "notes": m["notes"],
    }
    (CASES / f"{m['id']}.json").write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n")

d1 = {
    "caseId": "D1", "captureType": "CLOSE_DAY", "scenarioTag": "DAILY_ROLLUP",
    "input": {"endpoint": "POST /api/close-day", "body": {"date": DATE}},
    "precondition": "Đã xử lý xong 20 case trên đúng theo expectedUserAction của từng case.",
    "expectedOutput": {
        "date": DATE,
        "summary": {"revenue": revenue, "expense": expense,
                    "collected": collected, "receivable": receivable},
        "warningCount": len([w for w in warnings if w["status"] == "OPEN"]),
        "warnings": warnings,
    },
    "heroAssertions": [
        f"Tổng tiền vào KHÔNG phải doanh thu trong ngày = {non_revenue_inflow:,} đ "
        "(đặt cọc + tiền chủ hộ + khoản khác) — không được cộng vào revenue.",
        f"revenue = {revenue:,} đ chỉ gồm SALE đã CONFIRMED.",
        f"collected = {collected:,} đ gồm 1 đơn thu tiền mặt và 3 đơn được ghép từ chuyển khoản.",
        "R2 vẫn ở DRAFT nên 185.000đ KHÔNG được tính vào expense.",
        "M7 chưa ghép nên phải sinh warning UNMATCHED_MONEY.",
    ],
    "criticalFields": ["revenue", "expense", "collected", "receivable", "warningCount"],
    "notes": "Chốt lại toàn bộ: sai ở đây nghĩa là một trong các case trước bị map sai, "
             "hoặc logic recompute/đóng ngày sai.",
}
(CASES / "D1.json").write_text(json.dumps(d1, ensure_ascii=False, indent=2) + "\n")

tags = {}
for c in EVENTS + MOVES:
    tags[c["tag"]] = tags.get(c["tag"], 0) + 1

manifest = {
    "name": "TaxBridge PoC — bộ eval AI extraction",
    "simulatedDate": DATE, "timezone": "Asia/Ho_Chi_Minh",
    "vertical": "Đặc sản Tây Bắc (bán lẻ, ít SKU)",
    "business": SHOP, "ownerNameOnTransferScreenshots": OWNER,
    "synthetic": True,
    "caseCount": len(EVENTS) + len(MOVES) + 1,
    "byCaptureType": {
        "TEXT": len([e for e in EVENTS if e["ct"] == "TEXT"]),
        "AUDIO": len([e for e in EVENTS if e["ct"] == "AUDIO"]),
        "IMAGE_RECEIPT": len([e for e in EVENTS if e["ct"] == "IMAGE_RECEIPT"]),
        "IMAGE_TRANSFER": len(MOVES),
        "CLOSE_DAY": 1,
    },
    "scenarioTags": dict(sorted(tags.items())),
    "expectedDailyTotals": d1["expectedOutput"]["summary"],
    "nonRevenueInflowTotal": non_revenue_inflow,
    "pendingHumanWork": [
        "Thu 4 file audio theo out/audio_scripts.md (A1–A4), đặt vào evidence/",
        "Chạy mix_noise.sh cho A2 ở SNR 12dB",
    ],
    "notice": "Toàn bộ ảnh/audio là fixture tổng hợp, thương hiệu ngân hàng và mọi "
              "tên/số tài khoản/mã giao dịch đều hư cấu. Không dùng ngoài mục đích test.",
}
(ROOT / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")

print(f"cases: {len(list(CASES.glob('*.json')))}")
print(f"revenue={revenue:,}  expense={expense:,}  collected={collected:,}  receivable={receivable:,}")
print(f"non-revenue inflow={non_revenue_inflow:,}  warnings={len(warnings)}")
print("tags:", json.dumps(tags, ensure_ascii=False))
