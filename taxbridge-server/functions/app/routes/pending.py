from flask import g

from .. import report_service
from . import bp


@bp.get("/pending")
def get_pending():
    return report_service.pending(g.business_id)
