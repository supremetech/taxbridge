"""Blueprint `/api` dùng chung cho mọi route module."""

from flask import Blueprint, request

from .. import errors

bp = Blueprint("api", __name__, url_prefix="/api")


def json_body() -> dict:
    body = request.get_json(silent=True)
    if not isinstance(body, dict):
        raise errors.validation("Body phải là JSON object.")
    return body


def required(body: dict, *fields: str) -> list:
    values = []
    for f in fields:
        value = body.get(f)
        if value is None or (isinstance(value, str) and not value.strip()):
            raise errors.validation(f"Thiếu field {f}.")
        values.append(value)
    return values


@bp.get("/health")
def health():
    return {"ok": True}


from . import (auth, captures, close_day, dashboard, docs, events,  # noqa: E402,F401
               reconciliation, zalo)
