from flask import g, request

from .. import dashboard_service
from . import bp


@bp.get("/dashboard")
def get_dashboard():
    return dashboard_service.dashboard(g.business_id, request.args.get("date"))
