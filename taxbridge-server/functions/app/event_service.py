"""BusinessEvent: list / get / update / confirm / reject (plan BE §5)."""

from datetime import datetime

from . import errors
from .dashboard_service import sync_record
from .firestore import business, date_of, now_iso

EVENT_TYPES = {"SALE", "PURCHASE", "DEPOSIT", "OWNER_MONEY", "UNKNOWN"}
PAYMENT_METHODS = {"CASH", "BANK", "UNKNOWN"}
PAYMENT_STATUSES = {"UNPAID", "PAID", "UNKNOWN"}
EVENT_STATUSES = {"DRAFT", "CONFIRMED", "REJECTED"}

# Chỉ 7 field này sửa được qua PUT (contract/endpoints.md).
UPDATABLE = {"type", "amount", "description", "counterparty",
             "paymentMethod", "paymentStatus", "occurredAt"}


def to_dto(e: dict) -> dict:
    return {
        "eventId": e["eventId"],
        "type": e["type"],
        "status": e["status"],
        "amount": e["amount"],
        "description": e.get("description"),
        "counterparty": e.get("counterparty"),
        "paymentMethod": e.get("paymentMethod"),
        "paymentStatus": e.get("paymentStatus"),
        "occurredAt": e.get("occurredAt"),
        "source": e.get("source"),
        "captureType": e.get("captureType"),
        "evidenceText": e.get("evidenceText"),
        "evidenceUrl": e.get("evidenceUrl"),
        "confidence": e.get("confidence"),
    }


def events_ref(business_id: str):
    return business(business_id).collection("events")


def all_events(business_id: str) -> list[dict]:
    return [d.to_dict() for d in events_ref(business_id).stream()]


def get(business_id: str, event_id: str) -> dict:
    doc = events_ref(business_id).document(event_id).get()
    if not doc.exists:
        raise errors.not_found("Không tìm thấy giao dịch.")
    return doc.to_dict()


def list_events(business_id: str, status: str | None) -> list[dict]:
    if status and status not in EVENT_STATUSES:
        raise errors.validation("status không hợp lệ.")
    items = [e for e in all_events(business_id) if not status or e["status"] == status]
    items.sort(key=lambda e: e.get("occurredAt") or "", reverse=True)
    return [to_dto(e) for e in items]


def update(business_id: str, event_id: str, body: dict) -> dict:
    event = get(business_id, event_id)
    if event["status"] != "DRAFT":
        raise errors.invalid_state("Chỉ sửa được bản nháp.")

    extra = set(body) - UPDATABLE
    if extra:
        raise errors.validation(f"Field không sửa được: {', '.join(sorted(extra))}.")

    patch = dict(body)
    if "type" in patch and patch["type"] not in EVENT_TYPES:
        raise errors.validation("type không hợp lệ.")
    if "paymentMethod" in patch and patch["paymentMethod"] not in PAYMENT_METHODS:
        raise errors.validation("paymentMethod không hợp lệ.")
    if "paymentStatus" in patch and patch["paymentStatus"] not in PAYMENT_STATUSES:
        raise errors.validation("paymentStatus không hợp lệ.")
    if "amount" in patch and (not isinstance(patch["amount"], int)
                              or isinstance(patch["amount"], bool) or patch["amount"] < 0):
        raise errors.validation("amount phải là số nguyên VND >= 0.")
    if "occurredAt" in patch:
        try:
            datetime.fromisoformat(patch["occurredAt"])
        except (TypeError, ValueError):
            raise errors.validation("occurredAt phải là ISO-8601 có timezone.")

    patch["updatedAt"] = now_iso()
    events_ref(business_id).document(event_id).update(patch)
    # Đổi ngày → sổ ngày cũ lẫn ngày mới đều phải đồng bộ lại (§12).
    for date in {date_of(event.get("occurredAt")), date_of(patch.get("occurredAt"))}:
        sync_record(business_id, date)
    return to_dto({**event, **patch})


def _set_status(business_id: str, event_id: str, status: str) -> dict:
    event = get(business_id, event_id)
    if event["status"] != "DRAFT":
        raise errors.invalid_state("Giao dịch không còn ở trạng thái nháp.")
    patch = {"status": status, "updatedAt": now_iso()}
    events_ref(business_id).document(event_id).update(patch)
    sync_record(business_id, date_of(event.get("occurredAt")))
    return to_dto({**event, **patch})


def confirm(business_id: str, event_id: str) -> dict:
    return _set_status(business_id, event_id, "CONFIRMED")


def reject(business_id: str, event_id: str) -> dict:
    return _set_status(business_id, event_id, "REJECTED")
