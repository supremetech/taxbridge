from flask import g, request

from .. import dashboard_service
from . import bp


@bp.post("/close-day")
def close_day():
    body = request.get_json(silent=True) or {}
    return dashboard_service.close_day(g.business_id, body.get("date"))


@bp.get("/daily-records")
def list_daily_records():
    return dashboard_service.list_records(g.business_id)


@bp.get("/daily-records/<date>")
def get_daily_record(date):
    return dashboard_service.get_record(g.business_id, date)
