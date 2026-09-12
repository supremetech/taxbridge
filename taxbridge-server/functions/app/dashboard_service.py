"""Dashboard, close day, daily record, đồng bộ sổ ngày (plan BE §7–8, §12).

Tính khi đọc, không ledger. Module này đọc Firestore trực tiếp (không import
`event_service` / `reconciliation_service`) vì hai module đó gọi `sync_record`.
"""

from . import errors
from .firestore import business, date_of, now_iso, today


def _all_events(business_id: str) -> list[dict]:
    return [d.to_dict() for d in business(business_id).collection("events").stream()]


def _all_movements(business_id: str) -> list[dict]:
    return [d.to_dict() for d in business(business_id).collection("money_movements").stream()]


def _events(business_id: str, date: str) -> list[dict]:
    return [e for e in _all_events(business_id) if date_of(e.get("occurredAt")) == date]


def _movements(business_id: str, date: str) -> list[dict]:
    return [m for m in _all_movements(business_id) if date_of(m.get("occurredAt")) == date]


def money(amount: int) -> str:
    return f"{amount:,}".replace(",", ".") + "đ"


def check_date(date: str | None) -> str:
    date = date or today()
    if len(date) != 10 or date[4] != "-" or date[7] != "-":
        raise errors.validation("date phải có dạng YYYY-MM-DD.")
    return date


def summary(events: list[dict]) -> dict:
    sales = [e for e in events if e["type"] == "SALE" and e["status"] == "CONFIRMED"]
    revenue = sum(e["amount"] for e in sales)
    collected = sum(e["amount"] for e in sales if e.get("paymentStatus") == "PAID")
    expense = sum(e["amount"] for e in events
                  if e["type"] == "PURCHASE" and e["status"] == "CONFIRMED")
    return {"revenue": revenue, "expense": expense,
            "collected": collected, "receivable": revenue - collected}


def _past(items: list[dict], date: str, status: str) -> int:
    """Đếm bản ghi còn tồn đọng ở các ngày TRƯỚC `date` (Phase 2 ③, plan BE §14)."""
    return sum(1 for i in items
               if i["status"] == status and "" < date_of(i.get("occurredAt")) < date)


def dashboard(business_id: str, date: str | None) -> dict:
    date = check_date(date)
    # Đọc cả collection một lần: số của ngày và số tồn đọng ngày trước dùng chung dữ liệu.
    events, movements = _all_events(business_id), _all_movements(business_id)
    day_events = [e for e in events if date_of(e.get("occurredAt")) == date]
    day_movements = [m for m in movements if date_of(m.get("occurredAt")) == date]
    return {
        "date": date,
        **summary(day_events),
        # bankIn: mọi movement IN bất kể status (CLAUDE.md §6).
        "bankIn": sum(m["amount"] for m in day_movements if m["direction"] == "IN"),
        "draftCount": sum(1 for e in day_events if e["status"] == "DRAFT"),
        "unmatchedMoneyCount": sum(1 for m in day_movements if m["status"] == "UNMATCHED"),
        "pastDraftCount": _past(events, date, "DRAFT"),
        "pastUnmatchedCount": _past(movements, date, "UNMATCHED"),
    }


# --- Daily record ---------------------------------------------------------

def _records_ref(business_id: str):
    return business(business_id).collection("daily_records")


def _warning(type_: str, resource_type: str, resource_id: str, amount: int) -> dict:
    message = (f"Khoản tiền {money(amount)} chưa được phân loại."
               if type_ == "UNMATCHED_MONEY"
               else f"Giao dịch {money(amount)} chưa được xác nhận.")
    return {"warningId": f"{type_}:{resource_id}", "type": type_, "status": "OPEN",
            "resourceType": resource_type, "resourceId": resource_id, "amount": amount,
            "message": message, "resolvedAt": None}


def close_day(business_id: str, date: str | None) -> dict:
    """Đóng ngày = tạo record nếu chưa có, rồi đồng bộ (§12). Gọi lại = upsert."""
    date = check_date(date)
    ref = _records_ref(business_id).document(date)
    if not ref.get().exists:
        ts = now_iso()
        ref.set({"date": date, "summary": summary([]), "warningCount": 0, "warnings": [],
                 "closedAt": ts, "updatedAt": ts})
    return sync_record(business_id, date)


def sync_record(business_id: str, date: str | None) -> dict | None:
    """Sổ ngày `date` đổi dữ liệu → thêm warning mới, đóng warning hết lý do, recompute summary.

    Gọi sau mọi tạo / confirm / reject / match / classify / đổi ngày. Ngày **chưa đóng**
    (chưa có record) → không tạo gì, trả None (plan BE §12).
    """
    date = (date or "")[:10]
    if not date:
        return None
    ref = _records_ref(business_id).document(date)
    doc = ref.get()
    if not doc.exists:
        return None

    record = doc.to_dict()
    events, movements = _events(business_id, date), _movements(business_id, date)
    warnings = {w["warningId"]: w for w in record.get("warnings", [])}
    still_open = set()
    for m in movements:
        if m["status"] == "UNMATCHED":
            w = _warning("UNMATCHED_MONEY", "MONEY_MOVEMENT", m["movementId"], m["amount"])
            warnings.setdefault(w["warningId"], w)
            still_open.add(w["warningId"])
    for e in events:
        if e["status"] == "DRAFT":
            w = _warning("DRAFT_EVENT", "EVENT", e["eventId"], e["amount"])
            warnings.setdefault(w["warningId"], w)
            still_open.add(w["warningId"])

    ts = now_iso()
    # Resource hết DRAFT / UNMATCHED, bị xoá, hoặc đã dời sang ngày khác → warning hết lý do.
    for warning_id, w in warnings.items():
        if w["status"] == "OPEN" and warning_id not in still_open:
            w["status"], w["resolvedAt"] = "RESOLVED", ts

    items = list(warnings.values())
    patch = {"summary": summary(events), "warnings": items,
             "warningCount": sum(1 for w in items if w["status"] == "OPEN"), "updatedAt": ts}
    ref.update(patch)
    return {**record, **patch}


def list_records(business_id: str) -> list[dict]:
    records = [d.to_dict() for d in _records_ref(business_id).stream()]
    records.sort(key=lambda r: r["date"], reverse=True)
    return records


def get_record(business_id: str, date: str) -> dict:
    doc = _records_ref(business_id).document(check_date(date)).get()
    if not doc.exists:
        raise errors.not_found("Chưa có sổ ngày này.")
    return doc.to_dict()
