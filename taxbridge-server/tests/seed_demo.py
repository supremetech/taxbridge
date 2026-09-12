"""Seed account demo + lịch sử ngày cho prod (plan BE §11 Phase 6).

Chạy được nhiều lần: event dùng id cố định `ev_seed_*` nên không nhân bản; close-day là upsert.

    cd taxbridge-server
    BASE=https://asia-southeast1-hackathon-42790.cloudfunctions.net/api \
      functions/venv/bin/python tests/seed_demo.py

Cần ADC (`gcloud auth application-default login`) để ghi event ngày cũ thẳng vào Firestore —
capture luôn đặt `occurredAt = now()` nên không tạo được lịch sử qua API.
Mọi SALE seed đều `PAID`: event `SALE + CONFIRMED + UNPAID` sẽ thành candidate của tiền vào
hôm nay và phá hero UC5, nên không seed đơn còn nợ.
"""

import os
import sys

import firebase_admin
import requests
from firebase_admin import firestore

BASE = os.environ.get("BASE", "https://asia-southeast1-hackathon-42790.cloudfunctions.net/api")
USERNAME, PASSWORD = os.environ.get("SEED_USER", "tuan"), os.environ.get("SEED_PASS", "123456")

# (date, giờ, type, amount, description, counterparty, paymentMethod)
EVENTS = [
    ("2026-09-09", "09:30", "SALE", 1200000, "Bán 4 hộp collagen", "cô Hoa", "BANK"),
    ("2026-09-09", "11:00", "PURCHASE", 300000, "Mua bao bì", "Cửa hàng bao bì ABC", "CASH"),
    ("2026-09-09", "15:10", "SALE", 350000, "Bán 1 hộp yến chưng", "chị Hương", "CASH"),
    ("2026-09-10", "10:20", "SALE", 850000, "Bán 2 hộp collagen", "anh Dũng", "BANK"),
    ("2026-09-10", "16:40", "SALE", 400000, "Bán 1 thùng nước yến", "chị Mai", "CASH"),
    ("2026-09-11", "09:50", "SALE", 2100000, "Bán 7 hộp collagen", "cô Lan", "BANK"),
    ("2026-09-11", "14:15", "PURCHASE", 560000, "Nhập hàng collagen", "NCC Bình An", "CASH"),
]


def session() -> dict:
    r = requests.post(f"{BASE}/api/register", timeout=120,
                      json={"username": USERNAME, "password": PASSWORD})
    if r.status_code == 201:
        print(f"đã tạo account demo {USERNAME!r}")
        return r.json()
    if r.status_code == 409:
        r = requests.post(f"{BASE}/api/login", timeout=120,
                          json={"username": USERNAME, "password": PASSWORD})
        r.raise_for_status()
        print(f"account {USERNAME!r} đã có → login")
        return r.json()
    sys.exit(f"register lỗi {r.status_code}: {r.text}")


def main():
    s = session()
    business_id, token = s["businessId"], s["token"]

    os.environ.pop("FIRESTORE_EMULATOR_HOST", None)
    if not firebase_admin._apps:
        firebase_admin.initialize_app(None, {"projectId": "hackathon-42790"})
    events = (firestore.client().collection("businesses").document(business_id)
              .collection("events"))

    for i, (date, time, type_, amount, desc, party, method) in enumerate(EVENTS, 1):
        event_id = f"ev_seed_{date.replace('-', '')}_{i}"
        ts = f"{date}T{time}:00+07:00"
        events.document(event_id).set({
            "eventId": event_id, "type": type_, "status": "CONFIRMED", "amount": amount,
            "description": desc, "counterparty": party, "paymentMethod": method,
            "paymentStatus": "PAID", "occurredAt": ts, "source": "APP", "captureType": "TEXT",
            "evidenceText": None, "evidenceUrl": None, "confidence": 0.95,
            "sourceCaptureId": None, "createdAt": ts, "updatedAt": ts,
        })
    print(f"đã ghi {len(EVENTS)} event cho {len(set(e[0] for e in EVENTS))} ngày")

    headers = {"X-Session-Token": token}
    for date in sorted({e[0] for e in EVENTS}):
        r = requests.post(f"{BASE}/api/close-day", json={"date": date},
                          headers=headers, timeout=120)
        r.raise_for_status()
        rec = r.json()
        print(f"  {rec['date']}: revenue={rec['summary']['revenue']:>9,} "
              f"expense={rec['summary']['expense']:>8,} warning={rec['warningCount']}")

    r = requests.get(f"{BASE}/api/daily-records", headers=headers, timeout=120)
    print("daily-records:", [x["date"] for x in r.json()])
    print(f"\nxong. đăng nhập app bằng {USERNAME} / {PASSWORD}")


if __name__ == "__main__":
    main()
