"""Firestore client + helper id/thời gian.

Thời gian lưu **string ISO `+07:00`** (plan BE §2): DTO trả thẳng, lọc theo ngày = so 10
ký tự đầu, sort = so chuỗi.
"""

import secrets
from datetime import datetime
from zoneinfo import ZoneInfo

from firebase_admin import firestore as _fb_firestore

from .config import TZ_NAME

TZ = ZoneInfo(TZ_NAME)


class _LazyDb:
    """`firestore.client()` chỉ gọi được sau `initialize_app()` → resolve lúc dùng."""

    def __getattr__(self, name):
        return getattr(_fb_firestore.client(), name)


db = _LazyDb()


def new_id(prefix: str) -> str:
    return f"{prefix}_{secrets.token_hex(6)}"


def new_token() -> str:
    return "tb_" + secrets.token_urlsafe(32)


def now() -> datetime:
    return datetime.now(TZ)


def now_iso() -> str:
    return now().isoformat(timespec="seconds")


def today() -> str:
    return now().strftime("%Y-%m-%d")


def date_of(iso: str | None) -> str:
    """10 ký tự đầu của ISO string = ngày nghiệp vụ."""
    return (iso or "")[:10]


def business(business_id: str):
    return db.collection("businesses").document(business_id)
