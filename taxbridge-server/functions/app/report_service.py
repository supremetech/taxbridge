"""Báo cáo theo khoảng ngày + tồn đọng mọi ngày (plan BE §13, §14).

Đọc cả collection của business rồi lọc / gộp trong Python: PoC vài trăm doc, tránh
composite index (CLAUDE.md §6). `pending()` nằm đây chứ không ở `dashboard_service` vì nó
cần `to_dto` của event / movement, mà hai module đó lại import `dashboard_service`.
"""

from datetime import date

from . import errors, event_service, reconciliation_service
from .dashboard_service import check_date, summary
from .firestore import date_of

MAX_RANGE_DAYS = 92


def _bank_in(movements: list[dict]) -> int:
    """Mọi movement IN, bất kể status (CLAUDE.md §6)."""
    return sum(m["amount"] for m in movements if m["direction"] == "IN")


def _confirmed(events: list[dict], type_: str) -> list[dict]:
    return [e for e in events if e["type"] == type_ and e["status"] == "CONFIRMED"]


def _counts(events: list[dict], movements: list[dict]) -> dict:
    return {"bankIn": _bank_in(movements),
            "saleCount": len(_confirmed(events, "SALE")),
            "draftCount": sum(1 for e in events if e["status"] == "DRAFT"),
            "unmatchedMoneyCount": sum(1 for m in movements if m["status"] == "UNMATCHED")}


def report(business_id: str, from_: str | None, to: str | None) -> dict:
    if not from_ or not to:
        raise errors.validation("Thiếu from hoặc to.")
    from_, to = check_date(from_), check_date(to)
    try:
        days = (date.fromisoformat(to) - date.fromisoformat(from_)).days + 1
    except ValueError:
        raise errors.validation("from / to phải là ngày có thật.")
    if days < 1 or days > MAX_RANGE_DAYS:
        raise errors.validation("Khoảng tối đa 92 ngày, to >= from.")

    events = [e for e in event_service.all_events(business_id)
              if from_ <= date_of(e.get("occurredAt")) <= to]
    movements = [m for m in reconciliation_service.all_movements(business_id)
                 if from_ <= date_of(m.get("occurredAt")) <= to]

    by_day = []
    for day in sorted({date_of(x.get("occurredAt")) for x in events + movements}, reverse=True):
        day_events = [e for e in events if date_of(e.get("occurredAt")) == day]
        day_movements = [m for m in movements if date_of(m.get("occurredAt")) == day]
        day_summary = summary(day_events)
        by_day.append({"date": day, "revenue": day_summary["revenue"],
                       "expense": day_summary["expense"], "collected": day_summary["collected"],
                       **_counts(day_events, day_movements)})

    by_type = []
    for type_ in ("SALE", "PURCHASE", "DEPOSIT", "OWNER_MONEY", "UNKNOWN"):
        items = _confirmed(events, type_)
        if items:
            by_type.append({"type": type_, "amount": sum(e["amount"] for e in items),
                            "count": len(items)})

    return {"from": from_, "to": to, "days": days,
            "summary": {**summary(events), **_counts(events, movements),
                        "purchaseCount": len(_confirmed(events, "PURCHASE"))},
            "byDay": by_day, "byType": by_type}


def pending(business_id: str) -> dict:
    """Mọi DRAFT event + UNMATCHED movement, cũ nhất trước, kèm đếm theo ngày (§14)."""
    events = [e for e in event_service.all_events(business_id) if e["status"] == "DRAFT"]
    events.sort(key=lambda e: e.get("occurredAt") or "")
    # list_movements sort giảm dần và đã kèm candidates → đảo lại cho cũ nhất trước.
    movements = list(reversed(reconciliation_service.list_movements(business_id, "UNMATCHED")))

    by_date: dict[str, dict] = {}
    for e in events:
        by_date.setdefault(date_of(e.get("occurredAt")),
                           {"draftCount": 0, "unmatchedCount": 0})["draftCount"] += 1
    for m in movements:
        by_date.setdefault(date_of(m.get("occurredAt")),
                           {"draftCount": 0, "unmatchedCount": 0})["unmatchedCount"] += 1

    return {"draftEvents": [event_service.to_dto(e) for e in events],
            "unmatchedMovements": movements,
            "byDate": [{"date": d, **counts} for d, counts in sorted(by_date.items())]}
