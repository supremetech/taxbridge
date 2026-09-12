from flask import g, request

from .. import reconciliation_service
from . import bp, json_body, required


@bp.get("/money-movements")
def list_movements():
    return reconciliation_service.list_movements(g.business_id, request.args.get("status"))


@bp.get("/money-movements/<movement_id>")
def get_movement(movement_id):
    return reconciliation_service.get_dto(g.business_id, movement_id)


@bp.post("/money-movements/<movement_id>/match")
def match_movement(movement_id):
    (event_id,) = required(json_body(), "eventId")
    return reconciliation_service.match(g.business_id, movement_id, event_id)


@bp.post("/money-movements/<movement_id>/classify")
def classify_movement(movement_id):
    (classification_type,) = required(json_body(), "type")
    return reconciliation_service.classify(g.business_id, movement_id, classification_type)
