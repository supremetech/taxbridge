#!/usr/bin/env python3
"""
Chấm điểm bộ eval TaxBridge: so actual với expected, xuất report + phiếu chấm tay.

    python3 score.py runs/2026-09-11/actual.json

actual.json có dạng {"T1": {...DTO backend trả về...}, "M1": {...}, "D1": {...}}.
Với case money movement, thêm "candidates": [{"eventId": "...", "score": 0.9}, ...]
đúng như API trả; với case không được tạo event thì để null hoặc bỏ trống.

Chỉ chấm CRITICAL FIELD tự động. Soft field (description/counterparty) được xuất ra
`human_grading.md` để người chấm — theo đúng thỏa thuận của team.
"""
import json, pathlib, sys, collections, datetime

ROOT = pathlib.Path(__file__).parent
CASES = sorted((ROOT / "cases").glob("*.json"))

actual_path = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "runs/latest/actual.json")
if not actual_path.is_absolute():
    actual_path = ROOT / actual_path
ACT = json.loads(actual_path.read_text())
OUTDIR = actual_path.parent

rows, field_stat = [], collections.defaultdict(lambda: [0, 0])   # field -> [đúng, tổng]
conf_type = collections.Counter()      # (expected, actual) cho BusinessEvent.type
conf_class = collections.Counter()     # (expected, actual) cho classificationType
match_stat = {"top1_hit": 0, "top1_total": 0, "candset_ok": 0, "candset_total": 0,
              "wrong_automatch": 0}
trap = {"hit": 0, "total": 0}
soft_rows = []


def norm(v):
    return v.strip().upper() if isinstance(v, str) else v


for cp in CASES:
    c = json.loads(cp.read_text())
    cid = c["caseId"]
    a = ACT.get(cid)
    exp = c.get("expectedOutput")
    crit = c.get("criticalFields", [])
    miss, wrong = [], []

    # ── case kỳ vọng KHÔNG tạo event (A4, R3) ────────────────────────────────
    if c.get("expectNoEvent"):
        created = bool(a) and (a.get("type") not in (None, "UNKNOWN"))
        ok = not created
        rows.append((cid, c["scenarioTag"], "PASS" if ok else "FAIL",
                     "" if ok else f"đã bịa ra event type={a.get('type')} amount={a.get('amount')}"))
        continue

    if a is None:
        rows.append((cid, c["scenarioTag"], "FAIL", "không có output trong actual.json"))
        for f in crit:
            field_stat[f][1] += 1
        continue

    # ── D1: so summary ───────────────────────────────────────────────────────
    if cid == "D1":
        es, as_ = exp["summary"], (a.get("summary") or {})
        for f in ["revenue", "expense", "collected", "receivable"]:
            field_stat[f][1] += 1
            if es[f] == as_.get(f):
                field_stat[f][0] += 1
            else:
                wrong.append(f"{f}: expected {es[f]:,} / actual {as_.get(f)}")
        field_stat["warningCount"][1] += 1
        if exp["warningCount"] == a.get("warningCount"):
            field_stat["warningCount"][0] += 1
        else:
            wrong.append(f"warningCount: expected {exp['warningCount']} / actual {a.get('warningCount')}")
        rows.append((cid, c["scenarioTag"], "PASS" if not wrong else "FAIL", "; ".join(wrong)))
        continue

    # ── critical fields ──────────────────────────────────────────────────────
    for f in crit:
        field_stat[f][1] += 1
        e_, a_ = norm(exp.get(f)), norm(a.get(f))
        if e_ == a_:
            field_stat[f][0] += 1
        else:
            wrong.append(f"{f}: expected {exp.get(f)} / actual {a.get(f)}")

    if "type" in crit:
        conf_type[(exp.get("type"), a.get("type"))] += 1

    # ── money movement: matching + bẫy counterparty + classify ───────────────
    if c["captureType"] == "IMAGE_TRANSFER":
        em = c["expectedMatching"]
        cand_act = [x.get("eventId") for x in (a.get("candidates") or [])]
        if em["expectedCandidateEventIds"]:
            match_stat["candset_total"] += 1
            if set(em["expectedCandidateEventIds"]) <= set(cand_act):
                match_stat["candset_ok"] += 1
            else:
                wrong.append(f"candidates: expected ⊇ {em['expectedCandidateEventIds']} / actual {cand_act}")
        if em["expectedTop1"]:
            match_stat["top1_total"] += 1
            if cand_act[:1] == [em["expectedTop1"]]:
                match_stat["top1_hit"] += 1
            else:
                wrong.append(f"top1: expected {em['expectedTop1']} / actual {cand_act[:1]}")
        if not em["autoMatchAllowed"] and a.get("matchedEventId"):
            match_stat["wrong_automatch"] += 1
            wrong.append(f"TỰ GHÉP SAI: đã ghép {a['matchedEventId']} dù không được phép auto-match")

        t = c["counterpartyTrap"]
        if t["mustNotReturn"]:
            trap["total"] += 1
            if norm(a.get("counterparty")) == norm(t["mustNotReturn"]):
                trap["hit"] += 1
                wrong.append(f"DÍNH BẪY TÊN: counterparty = '{a.get('counterparty')}' (là chủ shop)")

        if exp.get("classificationType") or a.get("classificationType"):
            conf_class[(c["expectedUserAction"].get("type"), a.get("classificationType"))] += 1

    rows.append((cid, c["scenarioTag"], "PASS" if not wrong else "FAIL", "; ".join(wrong)))

    for f in c.get("softFields_gradedByHuman", []):
        soft_rows.append((cid, f, exp.get(f), a.get(f)))

# ── tổng hợp ─────────────────────────────────────────────────────────────────
npass = sum(1 for r in rows if r[2] == "PASS")
lines = [f"# Kết quả eval — {datetime.datetime.now():%Y-%m-%d %H:%M}", "",
         f"**Case pass: {npass}/{len(rows)}** ({npass/len(rows)*100:.0f}%)", "",
         "## Theo case", "", "| Case | Tình huống | KQ | Sai ở đâu |", "|---|---|---|---|"]
lines += [f"| {c} | {t} | {'✅' if s=='PASS' else '❌'} | {d or ''} |" for c, t, s, d in rows]

lines += ["", "## Độ chính xác theo field (critical, tự động)", "",
          "| Field | Đúng/Tổng | % |", "|---|---|---|"]
for f, (ok, tot) in sorted(field_stat.items()):
    lines.append(f"| {f} | {ok}/{tot} | {ok/tot*100:.0f}% |" if tot else f"| {f} | – | – |")

lines += ["", "## Ghép tiền vào (hero use case)", ""]
if match_stat["top1_total"]:
    lines.append(f"- Top-1 đúng: {match_stat['top1_hit']}/{match_stat['top1_total']}")
if match_stat["candset_total"]:
    lines.append(f"- Trả đủ candidate kỳ vọng: {match_stat['candset_ok']}/{match_stat['candset_total']}")
lines.append(f"- Tự ghép khi KHÔNG được phép: {match_stat['wrong_automatch']} lần "
             f"({'đạt' if match_stat['wrong_automatch']==0 else 'CẦN SỬA'})")
lines.append(f"- Dính bẫy lấy tên chủ shop làm counterparty: {trap['hit']}/{trap['total']} "
             f"({'đạt' if trap['hit']==0 else 'CẦN SỬA'})")

if conf_type:
    lines += ["", "## Confusion — BusinessEvent.type", "", "| Expected | Actual | Số ca |", "|---|---|---|"]
    lines += [f"| {e} | {a} | {n} |" for (e, a), n in sorted(conf_type.items(), key=lambda x: -x[1])]
if conf_class:
    lines += ["", "## Confusion — classificationType", "", "| Expected | Actual | Số ca |", "|---|---|---|"]
    lines += [f"| {e} | {a} | {n} |" for (e, a), n in sorted(conf_class.items(), key=lambda x: -x[1])]

lines += ["", "## Bước tiếp theo", "",
          "Gom các case FAIL theo NGUYÊN NHÂN CHUNG (không sửa lẻ từng case), "
          "sửa prompt/logic theo nguyên nhân đó, rồi chạy lại đúng bộ này để so trước/sau."]

(OUTDIR / "report.md").write_text("\n".join(lines) + "\n")
(OUTDIR / "run-report.json").write_text(json.dumps(
    {"pass": npass, "total": len(rows),
     "cases": [dict(zip(("caseId", "tag", "result", "diff"), r)) for r in rows],
     "fieldAccuracy": {f: {"ok": o, "total": t} for f, (o, t) in field_stat.items()},
     "matching": match_stat, "counterpartyTrap": trap},
    ensure_ascii=False, indent=2) + "\n")

hg = ["# Phiếu chấm tay — soft field", "",
      "Đánh dấu Đ/S cột cuối. Chấp nhận diễn đạt khác nếu đúng ý.", "",
      "| Case | Field | Expected | Actual | Đ/S |", "|---|---|---|---|---|"]
hg += [f"| {c} | {f} | {e} | {a} |  |" for c, f, e, a in soft_rows]
(OUTDIR / "human_grading.md").write_text("\n".join(hg) + "\n")

print(f"pass {npass}/{len(rows)} → {OUTDIR}/report.md")
