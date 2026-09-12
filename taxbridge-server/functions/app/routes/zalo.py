"""POST /api/zalo/webhook — luôn trả 200 để Zalo không gửi lại (contract §6)."""

import logging
import os

from flask import g, request

from .. import errors, zalo_service
from . import bp


@bp.post("/zalo/webhook")
def webhook():
    expected = os.environ.get("ZALO_WEBHOOK_SECRET", "")
    if not expected:
        # Bẫy CLAUDE.md §8: secret không mount → os.environ rỗng, không có lỗi để lần.
        # PoC chấp nhận đi tiếp (để demo không chết) nhưng phải log to.
        logging.warning("ZALO_WEBHOOK_SECRET chưa có — BỎ QUA kiểm tra secret webhook!")
    elif request.headers.get("X-Bot-Api-Secret-Token") != expected:
        raise errors.unauthorized("Sai secret token.")

    # Health probe gọi với body rỗng, không content-type → trả 200, không parse.
    zalo_service.handle(request.get_json(silent=True))
    return {"ok": True}


@bp.post("/zalo-users/<zalo_id>/replay")
def replay(zalo_id):
    """Xử lý lại message Zalo gửi trước khi link (contract §6.2)."""
    return zalo_service.replay(g.account_id, g.business_id, zalo_id)
