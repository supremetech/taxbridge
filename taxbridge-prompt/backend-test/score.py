#!/usr/bin/env python3
"""Chấm kết quả một vòng chạy back-end test, xuất report.md + run-report.json.

    python3 score.py runs/2026-09-12-baseline

Chỉ chấm assertion của variation chạy được (status=done). Variation BLOCKED (seed hỏng
vì AI) và ERROR (sự cố hạ tầng) không tính vào điểm back-end — đó là cả lý do bộ test
này tồn tại: tách "backend sai" khỏi "dữ liệu nhiễu".
"""
import collections, json, pathlib, statistics, sys

ROOT = pathlib.Path(__file__).parent
SEV_W = {"critical": 3, "major": 2, "minor": 1}

# variation ↔ use case demo (CLAUDE.md §9) — để trả lời "có dám lên sân khấu không"
UC_MAP = {
    "SC-CAND/V1-weights": ["UC4"], "SC-CAND/V2-threshold": ["UC4", "UC5"],
    "SC-CAND/V3-pool-filter": ["UC4"], "SC-CAND/V4-hero-no-candidate": ["UC5"],
    "SC-CAND/V5-ambiguous-two-candidates": ["UC4"], "SC-CAND/P1-name-normalize": ["UC4"],
    "SC-HERO/V1-match-effects": ["UC4"], "SC-HERO/V2-classify-deposit": ["UC5"],
    "SC-HERO/V3-classify-owner-money": ["UC5"], "SC-HERO/V4-bankin-all-status": ["UC4", "UC5"],
    "SC-HERO/V5-state-guards": ["UC4", "UC5"], "SC-HERO/V6-invalid-input": ["UC4", "UC5"],
    "SC-HERO/P2-match-target": ["UC4"],
    "SC-CLOSE/V1-generate-and-resolve": ["UC7"], "SC-CLOSE/V2-classify-keeps-summary": ["UC5", "UC7"],
    "SC-CLOSE/V3-reclose-upsert": ["UC7"], "SC-CLOSE/V4-history-and-errors": ["UC7"],
    "SC-DASH/V1-formula": ["UC2", "UC6"], "SC-DASH/V2-date-filter": ["UC2"],
    "SC-DASH/V3-empty-business": ["UC1"],
    "SC-DATE/V1-image-date-wins": ["UC10"], "SC-DATE/V2-text-without-date-is-today": ["UC2", "UC10"],
    "SC-DATE/P3-text-with-date": ["UC10"],
    "SC-REPORT/V1-report-totals": ["UC12"], "SC-REPORT/V2-report-validation": ["UC12"],
    "SC-REPORT/V3-pending-all-days": ["UC13"],
    "SC-BATCH/V1-batch-and-dedupe": ["UC14"], "SC-BATCH/V2-reject-single-receipt": ["UC14"],
    "SC-BATCH/V3-batch-then-single": ["UC14"], "SC-BATCH/V4-out-direction-not-in-bankin": ["UC14"],
}


def money_like(a):
    return any(k in (a.get("path") or "") for k in
               ("amount", "revenue", "expense", "collected", "receivable", "bankIn")) \
        or a.get("rule", "").startswith(("DASH-", "CLOSE-SUMMARY"))


def main(run_dir):
    d = ROOT / run_dir if not pathlib.Path(run_dir).is_absolute() else pathlib.Path(run_dir)
    actual = json.loads((d / "actual.json").read_text())
    rules = json.loads((ROOT / "rules.json").read_text())
    env = json.loads((d / "env.json").read_text()) if (d / "env.json").exists() else {}
    scen = {s["scenarioId"]: s for s in
            (json.loads(f.read_text()) for f in sorted((ROOT / "scenarios").glob("*.json")))}

    rows, fails, by_rule = [], [], collections.defaultdict(lambda: {"pass": 0, "fail": 0})
    by_group = collections.defaultdict(lambda: {"pass": 0, "fail": 0})
    n_pass = n_fail = 0
    money_ok = money_tot = 0
    uc = collections.defaultdict(lambda: {"pass": 0, "fail": 0, "blocked": 0})

    for sid, vars_ in actual.items():
        for vid, v in vars_.items():
            key = f"{sid}/{vid}"
            ok_n = sum(1 for a in v["asserts"] if a["ok"])
            bad = [a for a in v["asserts"] if not a["ok"]]
            for a in v["asserts"]:
                r = rules.get(a["rule"], {"group": "?", "severity": "minor"})
                by_rule[a["rule"]]["pass" if a["ok"] else "fail"] += 1
                by_group[r["group"]]["pass" if a["ok"] else "fail"] += 1
                if money_like(a):
                    money_tot += 1
                    money_ok += 1 if a["ok"] else 0
            n_pass += ok_n
            n_fail += len(bad)
            if v["status"] == "blocked":
                verdict = "BLOCKED"
            elif v["status"] == "error":
                verdict = "ERROR"
            elif bad:
                verdict = "FAIL"
            elif v.get("mode") == "probe":
                verdict = "PROBE"
            else:
                verdict = "PASS"
            for u in UC_MAP.get(key, []):
                uc[u]["blocked" if verdict in ("BLOCKED", "ERROR") else
                   ("fail" if verdict == "FAIL" else "pass")] += 1
            rows.append((key, verdict, ok_n, len(v["asserts"]), v.get("reason", "")))
            for a in bad:
                fails.append({**a, "where": key})

    crit = {r for r, s in by_rule.items() if s["fail"] and rules.get(r, {}).get("severity") == "critical"}
    hero = {r for r, s in by_rule.items() if s["fail"] and rules.get(r, {}).get("hero")}
    w_pass = sum(s["pass"] * SEV_W.get(rules.get(r, {}).get("severity", "minor"), 1)
                 for r, s in by_rule.items())
    w_tot = sum((s["pass"] + s["fail"]) * SEV_W.get(rules.get(r, {}).get("severity", "minor"), 1)
                for r, s in by_rule.items())
    blocked = [r for r in rows if r[1] in ("BLOCKED", "ERROR")]

    metrics = {
        "backendAccuracy": round(n_pass / (n_pass + n_fail), 4) if n_pass + n_fail else None,
        "healthScore": round(100 * w_pass / w_tot) if w_tot else None,
        "criticalViolations": len(crit),
        "heroViolations": len(hero),
        "wrongAutoMatchCount": by_rule.get("CAND-NO-AUTO", {}).get("fail", 0),
        "revenueInvarianceViolations": by_rule.get("CLS-REVENUE-INVARIANT", {}).get("fail", 0),
        "illegalTransitionSucceeded": by_rule.get("STATE-INVALID-409", {}).get("fail", 0),
        "moneyExactRate": round(money_ok / money_tot, 4) if money_tot else None,
        "blockedRate": round(len(blocked) / len(rows), 4) if rows else 0,
        "ruleCoverage": f"{len(by_rule)}/{len(rules)}",
        "weightRegression": weight_regression(actual),
    }

    lat = latency_table(env.get("latency", []))
    out = render(d.name, env, rows, by_group, by_rule, rules, fails, metrics, lat, uc, actual, scen)
    (d / "report.md").write_text(out)
    (d / "run-report.json").write_text(json.dumps(
        {"run": d.name, "metrics": metrics,
         "variations": [{"key": k, "verdict": v, "pass": p, "total": t, "reason": rs}
                        for k, v, p, t, rs in rows],
         "byRule": {r: {**s, "severity": rules.get(r, {}).get("severity"),
                        "hero": rules.get(r, {}).get("hero")} for r, s in by_rule.items()},
         "byGroup": dict(by_group), "failures": fails, "latency": lat},
        ensure_ascii=False, indent=2))
    ok = sum(1 for r in rows if r[1] in ("PASS", "PROBE"))
    print(f"variation {ok}/{len(rows)} đạt · assertion {n_pass}/{n_pass + n_fail} · "
          f"critical vi phạm {len(crit)} → {d}/report.md")
    return not crit


def weight_regression(actual):
    """Giải ngược (w_amount, w_name, w_day) từ 3 score quan sát ở SC-CAND/V1-weights."""
    try:
        v = actual["SC-CAND"]["V1-weights"]
        obs = [float(a["actual"]) for a in v["asserts"] if a["rule"] == "CAND-SCORE-FORMULA"]
        s1, s2, s3 = obs[0], obs[1], obs[2]          # A+N+D, A+N, A+D
        return {"w_amount": round(s2 + s3 - s1, 4), "w_name": round(s1 - s3, 4),
                "w_day": round(s1 - s2, 4), "spec": {"w_amount": 0.6, "w_name": 0.3, "w_day": 0.1}}
    except Exception:
        return None


def latency_table(samples):
    by = collections.defaultdict(list)
    for s in samples:
        by[(s["endpoint"], s["ai"])].append(s["ms"])
    out = []
    for (ep, ai), xs in sorted(by.items()):
        xs.sort()
        out.append({"endpoint": ep, "ai": ai, "n": len(xs),
                    "p50": int(statistics.median(xs)),
                    "p95": xs[min(len(xs) - 1, int(len(xs) * 0.95))], "max": max(xs)})
    return out


def render(name, env, rows, by_group, by_rule, rules, fails, m, lat, uc, actual, scen):
    L = [f"# Back-end test — {name}", ""]
    L.append(f"Base: `{env.get('baseUrl','?')}` · chạy lúc {env.get('startedAt','?')}")
    L += ["", "## 1. Độ hiệu quả xử lý back-end", "",
          f"**Điểm sức khỏe: {m['healthScore']}/100** "
          f"(trọng số critical ×3 · major ×2 · minor ×1)", "",
          "| Chỉ số | Giá trị |", "|---|---|",
          f"| Độ chính xác xử lý (assertion, đã loại BLOCKED) | {m['backendAccuracy']} |",
          f"| Rule critical bị vi phạm | {m['criticalViolations']} |",
          f"| Rule ảnh hưởng HERO bị vi phạm | {m['heroViolations']} |",
          f"| Tự ghép khi không được phép | {m['wrongAutoMatchCount']} (phải = 0) |",
          f"| Phân loại tiền làm đổi doanh thu | {m['revenueInvarianceViolations']} (phải = 0) |",
          f"| Chuyển trạng thái trái phép mà vẫn thành công | {m['illegalTransitionSucceeded']} (phải = 0) |",
          f"| Assertion về tiền khớp tuyệt đối | {m['moneyExactRate']} |",
          f"| Variation BLOCKED vì AI seed hỏng | {m['blockedRate']} (không tính vào điểm) |",
          f"| Độ phủ rule | {m['ruleCoverage']} |"]
    if m["weightRegression"]:
        w = m["weightRegression"]
        L += ["", f"**Trọng số thực tế giải ngược từ score quan sát:** "
                  f"`w_amount={w['w_amount']} · w_name={w['w_name']} · w_day={w['w_day']}` "
                  f"— spec: `0.6 / 0.3 / 0.1`."]

    L += ["", "## 2. Sẵn sàng cho demo (theo use case §9)", "", "| UC | Trạng thái | Chi tiết |", "|---|---|---|"]
    for u in sorted(uc):
        s = uc[u]
        st = "❌ BROKEN" if s["fail"] else ("⚠️ AT_RISK" if s["blocked"] else "✅ READY")
        L.append(f"| {u} | {st} | {s['pass']} đạt · {s['fail']} sai · {s['blocked']} blocked |")

    L += ["", "## 3. Theo nhóm rule", "", "| Nhóm | Assertion đạt/tổng | % |", "|---|---|---|"]
    for g, s in sorted(by_group.items()):
        tot = s["pass"] + s["fail"]
        L.append(f"| {g} | {s['pass']}/{tot} | {round(100*s['pass']/tot) if tot else 0}% |")

    L += ["", "## 4. Theo scenario / variation", "", "| Variation | KQ | Assertion | Ghi chú |", "|---|---|---|---|"]
    icon = {"PASS": "✅", "FAIL": "❌", "BLOCKED": "⛔", "ERROR": "💥", "PROBE": "🔎"}
    for k, v, p, t, rs in rows:
        L.append(f"| `{k}` | {icon[v]} {v} | {p}/{t} | {rs[:90]} |")

    L += ["", "## 5. Chi tiết sai, gom theo rule", ""]
    if not fails:
        L.append("Không có assertion nào sai.")
    for r in sorted({f["rule"] for f in fails}):
        meta = rules.get(r, {})
        L += [f"### `{r}` — {meta.get('severity','?')}"
              + (" · **HERO**" if meta.get("hero") else ""), "",
              f"- Rule: {meta.get('statement','?')}",
              f"- Nguồn: `{meta.get('source','?')}`"]
        for f in [x for x in fails if x["rule"] == r]:
            L.append(f"- `{f['where']}` — `{f.get('target','')}.{f.get('path','')}` "
                     f"{f['op']} `{f.get('value')}` → thực tế `{f['actual']}`"
                     + (f" · {f['note']}" if f.get("note") else ""))
        L.append("")

    L += ["## 6. Hành vi chưa định nghĩa (probe — không tính pass/fail)", ""]
    for sid, s in scen.items():
        for var in s["variations"]:
            if var.get("mode") != "probe":
                continue
            pr = var.get("probe", {})
            steps = actual.get(sid, {}).get(var["variationId"], {}).get("steps", {})
            L += [f"### `{sid}/{var['variationId']}`", "",
                  f"- Câu hỏi: {pr.get('question','')}",
                  f"- Ảnh hưởng: {pr.get('impact','')}"]
            for obs in pr.get("observe", []):
                sid_, _, path = obs.partition(".")
                body = steps.get(sid_, {}).get("body")
                from run import get_path
                L.append(f"- Quan sát `{obs}` = `{json.dumps(get_path(body, path), ensure_ascii=False)[:200]}`")
            L.append("")

    L += ["## 7. Độ trễ", "", "| Endpoint | Gọi AI | n | p50 | p95 | max |", "|---|---|---|---|---|---|"]
    for r in lat:
        L.append(f"| `{r['endpoint']}` | {'có' if r['ai'] else '—'} | {r['n']} | "
                 f"{r['p50']}ms | {r['p95']}ms | {r['max']}ms |")
    return "\n".join(L) + "\n"


if __name__ == "__main__":
    sys.path.insert(0, str(ROOT))
    sys.exit(0 if main(sys.argv[1] if len(sys.argv) > 1 else "runs/latest") else 1)
