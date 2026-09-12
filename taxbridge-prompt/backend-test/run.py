#!/usr/bin/env python3
"""Chạy các scenario back-end qua HTTP, ghi artifact cho score.py.

    python3 run.py --out runs/2026-09-12-baseline
    python3 run.py --only SC-DASH --out runs/smoke
    python3 run.py --dry-run

Mỗi variation chạy trên MỘT account mới (register rẻ, không gọi AI) nên kỳ vọng là
giá trị tuyệt đối, không phụ thuộc thứ tự chạy.
"""
import argparse, json, mimetypes, os, pathlib, re, secrets, ssl, sys, time, urllib.error, urllib.request
from datetime import datetime, timedelta, timezone

ROOT = pathlib.Path(__file__).parent
VN = timezone(timedelta(hours=7))
PROD = "https://asia-southeast1-hackathon-42790.cloudfunctions.net/api"
SEED_TEXT = "Bán 1 hộp trà 100 nghìn tiền mặt"
PUT_FIELDS = ["type", "amount", "description", "counterparty",
              "paymentMethod", "paymentStatus", "occurredAt"]
AI_PATHS = ("POST /api/captures",)   # endpoint có gọi AI — tách khỏi percentile logic thuần

# Python cài từ python.org không dùng CA store của macOS → trỏ thẳng vào bundle hệ thống.
SSL_CTX = ssl.create_default_context(
    cafile="/etc/ssl/cert.pem" if pathlib.Path("/etc/ssl/cert.pem").exists() else None)


# ─────────────────────────── HTTP ───────────────────────────

def http(method, url, token=None, json_body=None, raw_body=None, ctype=None, timeout=180):
    """Gọi API, trả (status, headers, body, ms). 4xx/5xx là dữ liệu test nên không raise."""
    data = None
    if json_body is not None:
        data = json.dumps(json_body, ensure_ascii=False).encode()
        ctype = "application/json"
    elif raw_body is not None:
        data = raw_body
    req = urllib.request.Request(url, data=data, method=method)
    if ctype:
        req.add_header("Content-Type", ctype)
    if token:
        req.add_header("X-Session-Token", token)
    t0 = time.monotonic()
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=SSL_CTX) as r:
            status, body, headers = r.status, r.read(), dict(r.headers)
    except urllib.error.HTTPError as e:
        status, body, headers = e.code, e.read(), dict(e.headers)
    except Exception as e:                      # lỗi mạng — ghi lại để variation thành ERROR
        return 0, {}, {"_error": repr(e)}, int((time.monotonic() - t0) * 1000)
    ms = int((time.monotonic() - t0) * 1000)
    try:
        parsed = json.loads(body) if body else None
    except json.JSONDecodeError:
        parsed = {"_raw": body[:500].decode("utf-8", "replace")}
    return status, headers, parsed, ms


def multipart(fields, filepath):
    """Dựng body multipart đúng hai field `type` + `file` (contract/endpoints.md)."""
    boundary = "----tb" + secrets.token_hex(8)
    out = b""
    for k, v in fields.items():
        out += (f"--{boundary}\r\nContent-Disposition: form-data; name=\"{k}\"\r\n\r\n"
                f"{v}\r\n").encode()
    name = filepath.name
    ct = mimetypes.guess_type(name)[0] or "application/octet-stream"
    out += (f"--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; "
            f"filename=\"{name}\"\r\nContent-Type: {ct}\r\n\r\n").encode()
    out += filepath.read_bytes() + f"\r\n--{boundary}--\r\n".encode()
    return out, f"multipart/form-data; boundary={boundary}"


# ─────────────────────────── biến & path ───────────────────────────

def today_offset(n=0):
    return (datetime.now(VN) + timedelta(days=n)).strftime("%Y-%m-%d")


def resolve(value, ctx):
    """Thay ${...} trong str/dict/list. Giữ nguyên kiểu số nếu cả chuỗi là một biến."""
    if isinstance(value, dict):
        return {k: resolve(v, ctx) for k, v in value.items()}
    if isinstance(value, list):
        return [resolve(v, ctx) for v in value]
    if not isinstance(value, str):
        return value
    whole = re.fullmatch(r"\$\{([^}]+)\}", value)
    if whole:
        return lookup_var(whole.group(1), ctx)
    return re.sub(r"\$\{([^}]+)\}", lambda m: str(lookup_var(m.group(1), ctx)), value)


def lookup_var(name, ctx):
    m = re.fullmatch(r"today([+-]\d+)?", name)
    if m:
        return today_offset(int(m.group(1)) if m.group(1) else 0)
    if name.startswith("env."):
        return os.environ.get(name[4:], "")
    if name.startswith("evidence."):
        _, key, field = name.split(".", 2)
        return ctx["evidence"][key][field]
    if name in ctx["vars"]:
        return ctx["vars"][name]
    if name.startswith("-") and name[1:] in ctx["vars"]:      # ${-AMT}
        return -ctx["vars"][name[1:]]
    # biểu thức số đơn giản: ${AMT-1}
    m = re.fullmatch(r"([A-Za-z_][\w]*)\s*([+-])\s*(\d+)", name)
    if m and m.group(1) in ctx["vars"]:
        base = ctx["vars"][m.group(1)]
        return base + int(m.group(3)) if m.group(2) == "+" else base - int(m.group(3))
    raise KeyError(f"biến chưa có: ${{{name}}}")


def get_path(obj, path):
    """a.b[0].c · a[*].b · a[?k=v].f — trả None nếu không có, list nếu dùng [*] hoặc [?]."""
    cur = obj
    if path in ("", None):
        return cur
    for part in re.findall(r"[^.\[\]]+|\[[^\]]*\]", path):
        if cur is None:
            return None
        if part.startswith("["):
            inner = part[1:-1]
            if inner == "*":
                cur = list(cur) if isinstance(cur, list) else None
            elif inner.startswith("?"):
                k, v = inner[1:].split("=", 1)
                hits = [x for x in (cur or []) if str(x.get(k)) == v]
                cur = hits[0] if len(hits) == 1 else (hits or None)
            else:
                idx = int(inner)
                cur = cur[idx] if isinstance(cur, list) and len(cur) > idx else None
        elif isinstance(cur, list):
            cur = [x.get(part) if isinstance(x, dict) else None for x in cur]
        elif isinstance(cur, dict):
            cur = cur.get(part)
        else:
            return None
    return cur


# ─────────────────────────── assertion ───────────────────────────

def target_value(spec, steps):
    """target = '<stepId>' | '<stepId>.status' | '<stepId>.ms'."""
    tgt = spec.get("target", "")
    if tgt.endswith(".status"):
        return steps[tgt[:-7]]["status"]
    if tgt.endswith(".ms"):
        return steps[tgt[:-3]]["ms"]
    return get_path(steps[tgt]["body"], spec.get("path"))


def check(spec, steps):
    """Trả (ok, mô tả thực tế)."""
    op = spec["op"]
    if op == "delta":
        a = get_path(steps[spec["from"]]["body"], spec["path"])
        b = get_path(steps[spec["to"]]["body"], spec["path"])
        if a is None or b is None:
            return False, f"thiếu giá trị ({a} → {b})"
        return (b - a) == spec["value"], f"{a} → {b} (delta {b - a})"
    if op == "diffOnlyKeys":
        a = steps[spec["from"]]["body"] or {}
        b = steps[spec["to"]]["body"] or {}
        diff = {k: [a.get(k), b.get(k)] for k in set(a) | set(b) if a.get(k) != b.get(k)}
        want = spec["value"]
        ok = set(diff) == set(want) and all(diff[k][1] - diff[k][0] == want[k] for k in want)
        return ok, f"đổi: {diff or 'không key nào'}"
    if op == "sameAs" or op == "differsFrom":
        ref = get_path(steps[spec["refTarget"]]["body"], spec["refPath"])
        act = target_value(spec, steps)
        same = act == ref
        return (same if op == "sameAs" else not same), f"{act!r} vs {ref!r}"

    act = target_value(spec, steps)
    val = spec.get("value")
    if op == "eq":
        return act == val, repr(act)
    if op == "neq":
        return act != val, repr(act)
    if op == "isNull":
        return act is None, repr(act)
    if op == "notNull":
        return act is not None, repr(act)
    if op == "approx":
        tol = spec.get("tol", 1e-6)
        return (isinstance(act, (int, float)) and abs(act - val) <= tol), repr(act)
    if op == "len":
        return (act is not None and len(act) == val), f"len={len(act) if act is not None else 'None'} {act!r}"
    if op == "contains":
        return (act is not None and val in act), repr(act)
    if op == "notContains":
        return (act is None or val not in act), repr(act)
    if op == "monotonicDesc":
        seq = [x for x in (act or []) if x is not None]
        return all(seq[i] >= seq[i + 1] for i in range(len(seq) - 1)), repr(seq)
    raise ValueError(f"op lạ: {op}")


# ─────────────────────────── runner ───────────────────────────

class Runner:
    def __init__(self, base, out, dry=False):
        self.base, self.out, self.dry = base.rstrip("/"), out, dry
        self.raw, self.log_lines, self.accounts, self.latency = [], [], [], []
        self.run_id = datetime.now(VN).strftime("%m%d%H%M") + secrets.token_hex(2)
        self.evidence = json.loads((ROOT / "evidence-index.json").read_text())
        self.ev_root = (ROOT / self.evidence["_root"]).resolve()

    def say(self, msg):
        print(msg, flush=True)
        self.log_lines.append(msg)

    def api(self, method, path, token=None, **kw):
        status, headers, body, ms = http(method, self.base + path, token=token, **kw)
        self.raw.append({"method": method, "path": path, "status": status,
                         "ms": ms, "req": kw.get("json_body"), "res": body})
        key = f"{method} /api{path.split('?')[0][4:]}" if path.startswith("/api") else f"{method} {path}"
        self.latency.append({"endpoint": key, "ms": ms, "ai": key in AI_PATHS})
        return {"status": status, "headers": headers, "body": body, "ms": ms}

    def new_account(self, label):
        username = f"tbtest_{self.run_id}_{label}"[:60]
        r = self.api("POST", "/api/register", json_body={"username": username, "password": "123456"})
        if r["status"] != 201 or not (r["body"] or {}).get("token"):
            raise RuntimeError(f"register thất bại: {r['status']} {r['body']}")
        self.accounts.append({"username": username, "businessId": r["body"]["businessId"]})
        return r["body"]["token"]

    # ---- các dạng bước ----

    def do_capture(self, step, token, ctx):
        cap = resolve(step["capture"], ctx)
        if "text" in cap:
            return self.api("POST", "/api/captures", token,
                            json_body={"type": cap["type"], "text": cap["text"]})
        e = self.evidence[cap["evidence"]]
        f = (ROOT / e["dir"] / e["file"]).resolve() if "dir" in e else self.ev_root / e["file"]
        body, ctype = multipart({"type": cap["type"]}, f)
        return self.api("POST", "/api/captures", token, raw_body=body, ctype=ctype)

    def do_seed_event(self, step, token, ctx):
        """capture TEXT → PUT ép 7 field → confirm/reject/giữ DRAFT. Trả (result, eventId, extra_asserts)."""
        spec = resolve(step["seedEvent"], ctx)
        cap = None
        for _ in range(2):                       # AI hỏng thì thử lại đúng một lần
            cap = self.api("POST", "/api/captures", token,
                           json_body={"type": "TEXT", "text": SEED_TEXT})
            if (cap["body"] or {}).get("status") == "DONE" and cap["body"].get("resultId"):
                break
        if (cap["body"] or {}).get("status") != "DONE":
            raise Blocked(f"seed capture FAILED: {(cap['body'] or {}).get('error')}")
        ev_id = cap["body"]["resultId"]
        payload = {k: spec[k] for k in PUT_FIELDS if k in spec}
        put = self.api("PUT", f"/api/events/{ev_id}", token, json_body=payload)
        if put["status"] != 200:
            raise Blocked(f"PUT seed thất bại: {put['status']} {put['body']}")
        extra = [{"rule": "EVENT-PUT-ECHO", "target": step["id"] + "__put", "path": k,
                  "op": "eq", "value": v, "note": "PUT phải áp dụng đúng field được phép"}
                 for k, v in payload.items()]
        if spec.get("confirm") is True:
            self.api("POST", f"/api/events/{ev_id}/confirm", token)
        elif spec.get("confirm") == "reject":
            self.api("POST", f"/api/events/{ev_id}/reject", token)
        return put, ev_id, extra

    def do_call(self, step, token, ctx):
        call = resolve(step["call"], ctx)
        method, path = call.split(" ", 1)
        body = resolve(step["json"], ctx) if "json" in step else None
        return self.api(method, path, token, **({"json_body": body} if body is not None else {}))

    # ---- một variation ----

    def run_variation(self, scen, var):
        label = f"{scen['scenarioId']}/{var['variationId']}"
        ctx = {"vars": {"runId": self.run_id}, "evidence": self.evidence}
        steps, asserts = {}, list(var.get("expect", []))
        token = self.new_account(var["variationId"].lower().replace("-", ""))
        t0 = time.monotonic()

        for step in var.get("seed", []) + var.get("act", []):
            sid = step["id"]
            if "seedEvent" in step:
                r, ev_id, extra = self.do_seed_event(step, token, ctx)
                steps[sid + "__put"] = r
                steps[sid] = r
                ctx["vars"][sid] = ev_id
                asserts.extend(extra)
            elif "capture" in step:
                r = self.do_capture(step, token, ctx)
                steps[sid] = r
            else:
                r = self.do_call(step, token, ctx)
                steps[sid] = r
            if r["status"] == 0:
                raise RuntimeError(f"lỗi mạng ở bước {sid}: {r['body']}")
            for pc in step.get("precheck", []):
                ok, actual = check({**resolve(pc, ctx), "target": sid}, steps)
                if not ok:
                    raise Blocked(f"precheck {sid}.{pc.get('path')} — {pc.get('why','')} "
                                  f"(thực tế {actual})")
            for k, jp in (step.get("save") or {}).items():
                jp, _, fmt = jp.partition("|")
                val = get_path(r["body"], jp.lstrip("$."))
                ctx["vars"][k] = val[:10] if fmt == "date" and val else val
            self.say(f"  {label:42s} {sid:10s} {r['status']} {r['ms']:5d}ms")

        results = []
        for a in asserts:
            a = resolve(a, ctx)
            try:
                ok, actual = check(a, steps)
            except Exception as e:
                ok, actual = False, f"lỗi chấm: {e}"
            results.append({**a, "ok": ok, "actual": actual})
        return {"status": "done", "asserts": results, "steps":
                {k: {"status": v["status"], "body": v["body"], "ms": v["ms"]} for k, v in steps.items()},
                "durationMs": int((time.monotonic() - t0) * 1000)}

    # ---- toàn bộ ----

    def run(self, only=None):
        scen_files = sorted((ROOT / "scenarios").glob("*.json"))
        rules = json.loads((ROOT / "rules.json").read_text())
        actual = {}
        if self.dry:
            return self.validate(scen_files, rules)

        warm = self.api("GET", "/api/health")
        self.say(f"health {warm['status']} {warm['ms']}ms (cold start, loại khỏi percentile)")
        self.latency.pop()

        for f in scen_files:
            scen = json.loads(f.read_text())
            if only and only not in scen["scenarioId"]:
                continue
            self.say(f"\n=== {scen['scenarioId']} — {scen['title']}")
            actual[scen["scenarioId"]] = {}
            for var in scen["variations"]:
                try:
                    res = self.run_variation(scen, var)
                except Blocked as e:
                    res = {"status": "blocked", "reason": str(e), "asserts": [], "steps": {}}
                    self.say(f"  BLOCKED {var['variationId']}: {e}")
                except Exception as e:
                    res = {"status": "error", "reason": repr(e), "asserts": [], "steps": {}}
                    self.say(f"  ERROR   {var['variationId']}: {e!r}")
                res["mode"] = var.get("mode", "assert")
                actual[scen["scenarioId"]][var["variationId"]] = res
                if res["status"] == "done":
                    bad = [a for a in res["asserts"] if not a["ok"]]
                    self.say(f"  → {var['variationId']}: {len(res['asserts']) - len(bad)}/"
                             f"{len(res['asserts'])} assert đạt" + (f" — SAI {len(bad)}" if bad else ""))
        self.write(actual)
        return actual

    def validate(self, scen_files, rules):
        errs = []
        for f in scen_files:
            scen = json.loads(f.read_text())
            for var in scen["variations"]:
                ids, known = set(), {"runId"}
                for s in var.get("seed", []) + var.get("act", []):
                    # biến phải được định nghĩa TRƯỚC khi dùng (bắt lỗi ${MDATE} dùng sớm)
                    for used in re.findall(r"\$\{([A-Za-z_][\w]*)", json.dumps(s, ensure_ascii=False)):
                        if used not in known and used != "today" and not used.startswith(("today", "env", "evidence")):
                            errs.append(f"{scen['scenarioId']}/{var['variationId']}: "
                                        f"bước {s['id']} dùng ${{{used}}} trước khi có")
                    known.add(s["id"])
                    known.update((s.get("save") or {}).keys())
                    ids.add(s["id"])
                    ids.add(s["id"] + "__put")
                for a in var.get("expect", []):
                    if a["rule"] not in rules:
                        errs.append(f"{scen['scenarioId']}/{var['variationId']}: rule lạ {a['rule']}")
                    for key in ("target", "from", "to", "refTarget"):
                        t = (a.get(key) or "").split(".")[0]
                        if t and t not in ids:
                            errs.append(f"{scen['scenarioId']}/{var['variationId']}: "
                                        f"{key} trỏ bước không có: {t}")
        print("\n".join(errs) if errs else f"dry-run OK — {len(scen_files)} scenario, 0 lỗi tham chiếu")
        return not errs

    def write(self, actual):
        d = ROOT / self.out
        d.mkdir(parents=True, exist_ok=True)
        (d / "actual.json").write_text(json.dumps(actual, ensure_ascii=False, indent=2))
        (d / "raw.json").write_text(json.dumps(self.raw, ensure_ascii=False, indent=2))
        (d / "run.log").write_text("\n".join(self.log_lines))
        (d / "accounts.json").write_text(json.dumps(self.accounts, ensure_ascii=False, indent=2))
        (d / "env.json").write_text(json.dumps(
            {"baseUrl": self.base, "runId": self.run_id,
             "startedAt": datetime.now(VN).isoformat(timespec="seconds"),
             "latency": self.latency}, ensure_ascii=False, indent=2))
        self.say(f"\nĐã ghi {d}/actual.json")


class Blocked(Exception):
    """Seed hỏng vì AI, không phải lỗi back-end."""


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--base", default=os.environ.get("TB_BASE", PROD))
    p.add_argument("--out", default="runs/latest")
    p.add_argument("--only")
    p.add_argument("--dry-run", action="store_true")
    args = p.parse_args()
    ok = Runner(args.base, args.out, args.dry_run).run(args.only)
    sys.exit(0 if ok else 1)
