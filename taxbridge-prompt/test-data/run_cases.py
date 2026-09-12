#!/usr/bin/env python3
"""Chạy 21 case eval AI qua API thật, gom `actual.json` cho `score.py`.

    python3 run_cases.py --out runs/2026-09-12-phase2

Mặc định tự `POST /api/register` một account mới cho mỗi vòng: sáng 12/09 hai vòng chạy
trên account dùng chung đã cho `warningCount` lệch nhau vì người khác thao tác cùng lúc.
`--user/--pass` để chạy trên account có sẵn nếu cần.

Phase 2 (②): ảnh mang **ngày in trên chứng từ** (bộ fixture là 11/09/2026) còn text/voice
không nêu ngày thì rơi vào hôm nay ⇒ một ngày nghiệp vụ của bộ case bị tách làm hai ngày
thật. Vì vậy 4 số của D1 lấy từ `GET /api/reports?from=<ngày nhỏ nhất>&to=<hôm nay>` và
`warningCount` = tổng warning OPEN của các sổ ngày đã đóng.
"""
import argparse, json, pathlib, secrets, ssl, subprocess, sys, time
from datetime import datetime, timedelta, timezone

TD = pathlib.Path(__file__).parent
VN = timezone(timedelta(hours=7))
PROD = "https://asia-southeast1-hackathon-42790.cloudfunctions.net/api"

# thứ tự theo giờ mô phỏng trong bộ case: đơn bán phải có trước khi tiền vào đi tìm candidate
ORDER = ["T3", "T4", "T1", "T2", "A1", "M1", "A2", "A3", "M2", "A4", "T5", "T6",
         "M3", "R1", "R2", "M4", "R3", "M5", "M6", "M7"]


def curl(args, timeout=180):
    r = subprocess.run(["curl", "-s", "--max-time", str(timeout)] + args,
                       capture_output=True, text=True)
    body = r.stdout.strip()
    try:
        return json.loads(body) if body else None
    except json.JSONDecodeError:
        return {"_raw": body[:300], "_stderr": r.stderr[:200]}


class Run:
    def __init__(self, base, out):
        self.base, self.out, self.log = base.rstrip("/"), out, []
        self.cases = {p.stem: json.loads(p.read_text()) for p in (TD / "cases").glob("*.json")}

    def say(self, m):
        print(m, flush=True)
        self.log.append(m)

    def api(self, method, path, json_body=None, form=None):
        args = ["-X", method, f"{self.base}/api{path}"]
        if self.token:
            args += ["-H", f"X-Session-Token: {self.token}"]
        if json_body is not None:
            args += ["-H", "Content-Type: application/json",
                     "-d", json.dumps(json_body, ensure_ascii=False)]
        for f in (form or []):
            args += ["-F", f]
        return curl(args)

    def login(self, user, pw):
        self.token = None
        if user:
            s = self.api("POST", "/login", {"username": user, "password": pw})
        else:
            user = f"eval_{datetime.now(VN):%m%d%H%M}_{secrets.token_hex(2)}"
            s = self.api("POST", "/register", {"username": user, "password": "123456"})
        self.token = s["token"]
        self.say(f"account {user} · business {s['businessId']}")
        return user

    def go(self):
        actual, raw, idmap, dates = {}, {}, {}, set()
        for cid in ORDER:
            c = self.cases[cid]
            t0 = time.time()
            if c["captureType"] == "TEXT":
                cap = self.api("POST", "/captures", {"type": "TEXT", "text": c["input"]["text"]})
            else:
                f = TD / c["input"]["evidenceFile"]
                cap = self.api("POST", "/captures", form=[f"type={c['captureType']}", f"file=@{f}"])
            dt = time.time() - t0
            raw[cid] = {"capture": cap}
            self.say(f"{cid:3s} {c['captureType']:14s} {dt:5.1f}s  {cap.get('status')} "
                     f"{cap.get('resultType')} {cap.get('occurredAt') or ''} {cap.get('error') or ''}")
            rid = cap.get("resultId")
            if not rid:
                actual[cid] = None
                continue
            is_event = cap.get("resultType") == "EVENT"
            dto = self.api("GET", f"/{'events' if is_event else 'money-movements'}/{rid}")
            raw[cid]["dto"] = dto
            actual[cid] = dto
            idmap[rid] = cid
            dates.add(dto["occurredAt"][:10])
            self.act(c, cid, rid, is_event, idmap)
            (TD / self.out).mkdir(parents=True, exist_ok=True)
            (TD / self.out / "raw.json").write_text(json.dumps(raw, ensure_ascii=False, indent=2))

        actual["D1"] = self.close_days(dates, raw)
        for dto in actual.values():                       # đổi id thật → caseId cho score.py
            if isinstance(dto, dict):
                for cand in dto.get("candidates") or []:
                    cand["eventId"] = idmap.get(cand["eventId"], cand["eventId"])
                if dto.get("matchedEventId") in idmap:
                    dto["matchedEventId"] = idmap[dto["matchedEventId"]]
        d = TD / self.out
        (d / "actual.json").write_text(json.dumps(actual, ensure_ascii=False, indent=2))
        (d / "raw.json").write_text(json.dumps(raw, ensure_ascii=False, indent=2))
        (d / "idmap.json").write_text(json.dumps(idmap, ensure_ascii=False, indent=2))
        (d / "run.log").write_text("\n".join(self.log))
        self.say(f"\nĐã ghi {d}/actual.json")

    def act(self, c, cid, rid, is_event, idmap):
        """Thực hiện expectedUserAction của case (confirm / match / classify / để nguyên)."""
        if is_event:
            if c.get("expectNoEvent"):
                self.api("POST", f"/events/{rid}/reject")
                self.say(f"    → AI bịa ra event, reject {rid}")
            elif c.get("expectedFinalStatus") == "CONFIRMED":
                r = self.api("POST", f"/events/{rid}/confirm")
                self.say(f"    → confirm: {r.get('status')}")
            else:
                self.say(f"    → giữ DRAFT (case cố ý để sinh warning)")
            return
        action = (c.get("expectedUserAction") or {}).get("action")
        if action == "match":
            target = c["expectedUserAction"]["toEventId"]
            ev = next((k for k, v in idmap.items() if v == target), None)
            if not ev:
                self.say(f"    → không match được: chưa có event cho {target}")
                return
            r = self.api("POST", f"/money-movements/{rid}/match", {"eventId": ev})
            self.say(f"    → match → {target}: {r.get('status')}")
        elif action == "classify":
            t = c["expectedUserAction"]["type"]
            r = self.api("POST", f"/money-movements/{rid}/classify", {"type": t})
            self.say(f"    → classify {t}: {r.get('status')}/{r.get('classificationType')}")
        else:
            self.say("    → để nguyên UNMATCHED")

    def close_days(self, dates, raw):
        """Đóng mọi ngày có bản ghi rồi gom 4 số qua /reports (Phase 2 ② tách ngày)."""
        today = datetime.now(VN).strftime("%Y-%m-%d")
        dates = sorted(dates | {today})
        warnings, records = 0, {}
        for d in dates:
            rec = self.api("POST", "/close-day", {"date": d})
            records[d] = rec
            open_n = sum(1 for w in rec.get("warnings", []) if w["status"] == "OPEN")
            warnings += open_n
            self.say(f"close-day {d}: warningCount {rec.get('warningCount')} (OPEN {open_n}) "
                     f"revenue {rec.get('summary', {}).get('revenue')}")
        rep = self.api("GET", f"/reports?from={dates[0]}&to={dates[-1]}")
        raw["D1"] = {"records": records, "report": rep}
        s = rep.get("summary", {})
        self.say(f"reports {dates[0]}..{dates[-1]}: " + json.dumps(s, ensure_ascii=False))
        return {"date": dates[-1], "summary": {k: s.get(k) for k in
                ("revenue", "expense", "collected", "receivable")},
                "warningCount": warnings, "_days": dates}


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--base", default=PROD)
    p.add_argument("--out", default="runs/latest")
    p.add_argument("--user")
    p.add_argument("--password", default="123456")
    a = p.parse_args()
    r = Run(a.base, a.out)
    r.login(a.user, a.password)
    r.go()
