"""MoneyMovement: candidates / match / classify (plan BE §6).

`candidates` tính lúc đọc, không persist.
"""

import re
import unicodedata

from . import errors, event_service
from .config import CANDIDATE_MIN_SCORE, MAX_CANDIDATES
from .dashboard_service import resolve_warnings
from .firestore import business, date_of, now_iso

CLASSIFICATION_TYPES = {"DEPOSIT", "OWNER_MONEY", "OTHER", "UNKNOWN"}
MOVEMENT_STATUSES = {"UNMATCHED", "MATCHED", "CLASSIFIED"}


def movements_ref(business_id: str):
    return business(business_id).collection("money_movements")


def all_movements(business_id: str) -> list[dict]:
    return [d.to_dict() for d in movements_ref(business_id).stream()]


def to_dto(m: dict, candidates: list[dict] | None = None) -> dict:
    return {
        "movementId": m["movementId"],
        "direction": m["direction"],
        "amount": m["amount"],
        "memo": m.get("memo"),
        "counterparty": m.get("counterparty"),
        "occurredAt": m.get("occurredAt"),
        "source": m.get("source"),
        "captureType": m.get("captureType"),
        "evidenceText": m.get("evidenceText"),
        "evidenceUrl": m.get("evidenceUrl"),
        "status": m["status"],
        "matchedEventId": m.get("matchedEventId"),
        "classificationType": m.get("classificationType"),
        "candidates": candidates or [],
    }


# --- Chấm điểm candidate --------------------------------------------------

def _tokens(s: str | None) -> set[str]:
    plain = unicodedata.normalize("NFD", s or "").encode("ascii", "ignore").decode().lower()
    return {t for t in re.split(r"[^a-z0-9]+", plain) if len(t) >= 2}


def similar(a: str | None, b: str | None) -> bool:
    """Trùng ít nhất một token không dấu (tên khách trong memo CK vs counterparty)."""
    return bool(_tokens(a) & _tokens(b))


def candidates_for(business_id: str, movement: dict, events: list[dict] | None = None) -> list[dict]:
    if movement["status"] != "UNMATCHED":
        return []
    events = events if events is not None else event_service.all_events(business_id)
    scored = []
    for e in events:
        if e["type"] != "SALE" or e["status"] != "CONFIRMED" or e.get("paymentStatus") != "UNPAID":
            continue
        score = 0.0
        if movement["amount"] == e["amount"]:
            score += 0.6
        if similar(movement.get("memo") or movement.get("counterparty"),
                   e.get("counterparty") or e.get("description")):
            score += 0.3
        if date_of(movement.get("occurredAt")) == date_of(e.get("occurredAt")):
            score += 0.1
        if score >= CANDIDATE_MIN_SCORE:
            scored.append({"eventId": e["eventId"], "description": e.get("description"),
                           "amount": e["amount"], "score": round(score, 2)})
    scored.sort(key=lambda c: c["score"], reverse=True)
    return scored[:MAX_CANDIDATES]


# --- Đọc ------------------------------------------------------------------

def get(business_id: str, movement_id: str) -> dict:
    doc = movements_ref(business_id).document(movement_id).get()
    if not doc.exists:
        raise errors.not_found("Không tìm thấy khoản tiền.")
    return doc.to_dict()


def get_dto(business_id: str, movement_id: str) -> dict:
    movement = get(business_id, movement_id)
    return to_dto(movement, candidates_for(business_id, movement))


def list_movements(business_id: str, status: str | None) -> list[dict]:
    if status and status not in MOVEMENT_STATUSES:
        raise errors.validation("status không hợp lệ.")
    items = [m for m in all_movements(business_id) if not status or m["status"] == status]
    items.sort(key=lambda m: m.get("occurredAt") or "", reverse=True)
    events = event_service.all_events(business_id) if items else []
    return [to_dto(m, candidates_for(business_id, m, events)) for m in items]


# --- Mutation -------------------------------------------------------------

def match(business_id: str, movement_id: str, event_id: str) -> dict:
    movement = get(business_id, movement_id)
    if movement["status"] != "UNMATCHED":
        raise errors.invalid_state("Khoản tiền đã được xử lý.")
    event = event_service.get(business_id, event_id)

    patch = {"status": "MATCHED", "matchedEventId": event_id}
    movements_ref(business_id).document(movement_id).update(patch)
    event_service.events_ref(business_id).document(event["eventId"]).update(
        {"paymentStatus": "PAID", "updatedAt": now_iso()})
    resolve_warnings(business_id, movement_id)
    return to_dto({**movement, **patch})


def classify(business_id: str, movement_id: str, classification_type: str) -> dict:
    if classification_type not in CLASSIFICATION_TYPES:
        raise errors.validation("type không hợp lệ.")
    movement = get(business_id, movement_id)
    if movement["status"] != "UNMATCHED":
        raise errors.invalid_state("Khoản tiền đã được xử lý.")

    # Không tạo event, không đổi revenue — hero moment (CLAUDE.md §1).
    patch = {"status": "CLASSIFIED", "classificationType": classification_type,
             "classifiedAt": now_iso()}
    movements_ref(business_id).document(movement_id).update(patch)
    resolve_warnings(business_id, movement_id)
    return to_dto({**movement, **patch})
