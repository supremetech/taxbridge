"""Dashboard, close day, daily record, resolve warning (plan BE §7–8).

Tính khi đọc, không ledger. Module này đọc Firestore trực tiếp (không import
`event_service` / `reconciliation_service`) vì hai module đó gọi `resolve_warnings`.
"""

from . import errors
from .firestore import business, date_of, now_iso, today


def _events(business_id: str, date: str) -> list[dict]:
    return [e for e in (d.to_dict() for d in business(business_id).collection("events").stream())
            if date_of(e.get("occurredAt")) == date]


def _movements(business_id: str, date: str) -> list[dict]:
    return [m for m in (d.to_dict() for d in
                        business(business_id).collection("money_movements").stream())
            if date_of(m.get("occurredAt")) == date]


def _money(amount: int) -> str:
    return f"{amount:,}".replace(",", ".") + "đ"


def check_date(date: str | None) -> str:
    date = date or today()
    if len(date) != 10 or date[4] != "-" or date[7] != "-":
        raise errors.validation("date phải có dạng YYYY-MM-DD.")
    return date


def _summary(events: list[dict]) -> dict:
    sales = [e for e in events if e["type"] == "SALE" and e["status"] == "CONFIRMED"]
    revenue = sum(e["amount"] for e in sales)
    collected = sum(e["amount"] for e in sales if e.get("paymentStatus") == "PAID")
    expense = sum(e["amount"] for e in events
                  if e["type"] == "PURCHASE" and e["status"] == "CONFIRMED")
    return {"revenue": revenue, "expense": expense,
            "collected": collected, "receivable": revenue - collected}


def dashboard(business_id: str, date: str | None) -> dict:
    date = check_date(date)
    events, movements = _events(business_id, date), _movements(business_id, date)
    summary = _summary(events)
    return {
        "date": date,
        **summary,
        # bankIn: mọi movement IN bất kể status (CLAUDE.md §6).
        "bankIn": sum(m["amount"] for m in movements if m["direction"] == "IN"),
        "draftCount": sum(1 for e in events if e["status"] == "DRAFT"),
        "unmatchedMoneyCount": sum(1 for m in movements if m["status"] == "UNMATCHED"),
    }


# --- Daily record ---------------------------------------------------------

def _records_ref(business_id: str):
    return business(business_id).collection("daily_records")


def _warning(type_: str, resource_type: str, resource_id: str, amount: int) -> dict:
    message = (f"Khoản tiền {_money(amount)} chưa được phân loại."
               if type_ == "UNMATCHED_MONEY"
               else f"Giao dịch {_money(amount)} chưa được xác nhận.")
    return {"warningId": f"{type_}:{resource_id}", "type": type_, "status": "OPEN",
            "resourceType": resource_type, "resourceId": resource_id, "amount": amount,
            "message": message, "resolvedAt": None}


def close_day(business_id: str, date: str | None) -> dict:
    date = check_date(date)
    events, movements = _events(business_id, date), _movements(business_id, date)

    doc = _records_ref(business_id).document(date).get()
    old = doc.to_dict() if doc.exists else {}
    # Upsert: warning đã RESOLVED giữ nguyên, warning mới thêm vào.
    warnings = {w["warningId"]: w for w in old.get("warnings", [])}
    for m in movements:
        if m["status"] == "UNMATCHED":
            w = _warning("UNMATCHED_MONEY", "MONEY_MOVEMENT", m["movementId"], m["amount"])
            warnings.setdefault(w["warningId"], w)
    for e in events:
        if e["status"] == "DRAFT":
            w = _warning("DRAFT_EVENT", "EVENT", e["eventId"], e["amount"])
            warnings.setdefault(w["warningId"], w)

    items = list(warnings.values())
    ts = now_iso()
    record = {"date": date, "summary": _summary(events),
              "warningCount": sum(1 for w in items if w["status"] == "OPEN"),
              "warnings": items, "closedAt": old.get("closedAt") or ts, "updatedAt": ts}
    _records_ref(business_id).document(date).set(record)
    return record


def list_records(business_id: str) -> list[dict]:
    records = [d.to_dict() for d in _records_ref(business_id).stream()]
    records.sort(key=lambda r: r["date"], reverse=True)
    return records


def get_record(business_id: str, date: str) -> dict:
    doc = _records_ref(business_id).document(check_date(date)).get()
    if not doc.exists:
        raise errors.not_found("Chưa có sổ ngày này.")
    return doc.to_dict()


def resolve_warnings(business_id: str, resource_id: str) -> None:
    """Sau confirm/reject/match/classify: đóng warning trỏ tới resource + recompute summary."""
    for doc in _records_ref(business_id).stream():
        record = doc.to_dict()
        warnings = record.get("warnings", [])
        hit = [w for w in warnings
               if w["status"] == "OPEN" and w["resourceId"] == resource_id]
        if not hit:
            continue
        ts = now_iso()
        for w in hit:
            w["status"], w["resolvedAt"] = "RESOLVED", ts
        doc.reference.update({
            "warnings": warnings,
            "warningCount": sum(1 for w in warnings if w["status"] == "OPEN"),
            "summary": _summary(_events(business_id, record["date"])),
            "updatedAt": ts,
        })
