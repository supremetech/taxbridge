"""POST /api/captures — JSON `{type: TEXT, text}` hoặc multipart `type` + `file`."""

from flask import g, request

from .. import capture_service, errors
from ..capture_service import CAPTURE_TYPES, UPLOAD_TYPES
from . import bp, json_body, required


@bp.post("/captures")
def create_capture():
    if request.files:
        capture_type = (request.form.get("type") or "").strip()
        if capture_type not in UPLOAD_TYPES:
            raise errors.validation("type phải là AUDIO | IMAGE_RECEIPT | IMAGE_TRANSFER.")
        file = request.files.get("file")
        if file is None:
            raise errors.validation("Thiếu field file.")
        data = file.read()
        capture_service.check_upload(capture_type, file.mimetype, data)
        return capture_service.process_capture(g.business_id, "APP", capture_type,
                                               file_bytes=data)

    body = json_body()
    capture_type = body.get("type")
    if capture_type not in CAPTURE_TYPES:
        raise errors.validation("type không hợp lệ.")
    if capture_type != "TEXT":
        raise errors.validation("Capture khác TEXT phải gửi bằng multipart kèm file.")
    (text,) = required(body, "text")
    return capture_service.process_capture(g.business_id, "APP", "TEXT", text=text)
