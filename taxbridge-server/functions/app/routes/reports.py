from flask import g, request

from .. import report_service
from . import bp


@bp.get("/reports")
def get_report():
    return report_service.report(g.business_id, request.args.get("from"),
                                 request.args.get("to"))
