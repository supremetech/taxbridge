from flask import g, request

from .. import event_service
from . import bp, json_body


@bp.get("/events")
def list_events():
    return event_service.list_events(g.business_id, request.args.get("status"))


@bp.get("/events/<event_id>")
def get_event(event_id):
    return event_service.to_dto(event_service.get(g.business_id, event_id))


@bp.put("/events/<event_id>")
def update_event(event_id):
    return event_service.update(g.business_id, event_id, json_body())


@bp.post("/events/<event_id>/confirm")
def confirm_event(event_id):
    return event_service.confirm(g.business_id, event_id)


@bp.post("/events/<event_id>/reject")
def reject_event(event_id):
    return event_service.reject(g.business_id, event_id)
