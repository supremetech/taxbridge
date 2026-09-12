"""Pipeline capture dùng chung cho app và Zalo (plan BE §4).

Xử lý đồng bộ, mọi việc xong trước khi trả response (Functions gen2 đóng băng CPU sau
response). AI lỗi → HTTP 200 + `status: FAILED`, không 5xx.
"""

import logging
import re
import subprocess
import tempfile

import imageio_ffmpeg

from . import errors, openai_client, storage
from .config import (AUDIO_CONTENT_TYPES, IMAGE_CONTENT_TYPES, MAX_AUDIO_SECONDS,
                     MAX_FILE_BYTES)
from .firestore import business, new_id, now_iso

CAPTURE_TYPES = {"TEXT", "AUDIO", "IMAGE_RECEIPT", "IMAGE_TRANSFER"}
UPLOAD_TYPES = {"AUDIO", "IMAGE_RECEIPT", "IMAGE_TRANSFER"}


# --- Validate upload (route gọi trước khi vào pipeline) -------------------

def _is_png(data: bytes) -> bool:
    return data[:8] == b"\x89PNG\r\n\x1a\n"


def _is_jpeg(data: bytes) -> bool:
    return data[:2] == b"\xff\xd8"


def _is_mp4(data: bytes) -> bool:
    return data[4:8] == b"ftyp"


def audio_seconds(data: bytes) -> float | None:
    """Đọc độ dài bằng ffmpeg; không đọc được → None (bỏ qua kiểm tra)."""
    try:
        with tempfile.TemporaryDirectory() as d:
            src = f"{d}/probe.m4a"
            with open(src, "wb") as f:
                f.write(data)
            out = subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(), "-i", src],
                                 capture_output=True, text=True, timeout=20).stderr
        m = re.search(r"Duration: (\d+):(\d+):(\d+\.?\d*)", out)
        if not m:
            return None
        h, mi, s = m.groups()
        return int(h) * 3600 + int(mi) * 60 + float(s)
    except Exception as e:
        logging.warning("không đọc được độ dài audio: %s", e)
        return None


def check_upload(capture_type: str, content_type: str | None, data: bytes) -> None:
    if len(data) > MAX_FILE_BYTES:
        raise errors.ApiError(413, "FILE_TOO_LARGE", "File vượt quá 10 MB.")
    if not data:
        raise errors.validation("File rỗng.")

    unsupported = errors.ApiError(415, "UNSUPPORTED_FILE_TYPE",
                                  "Chỉ nhận ảnh JPEG/PNG hoặc audio M4A.")
    if capture_type == "AUDIO":
        if not _is_mp4(data) and (content_type or "") not in AUDIO_CONTENT_TYPES:
            raise unsupported
        seconds = audio_seconds(data)
        if seconds is not None and seconds > MAX_AUDIO_SECONDS + 1:
            raise errors.ApiError(413, "FILE_TOO_LARGE", "Ghi âm dài quá 60 giây.")
    else:
        if not (_is_jpeg(data) or _is_png(data)) and (content_type or "") not in IMAGE_CONTENT_TYPES:
            raise unsupported


# --- Pipeline -------------------------------------------------------------

def _file_kind(capture_type: str, data: bytes) -> tuple[str, str]:
    if capture_type == "AUDIO":
        return "m4a", "audio/mp4"
    return ("png", "image/png") if _is_png(data) else ("jpg", "image/jpeg")


def _result(ref, capture_id: str, result_type=None, result_id=None, error=None) -> dict:
    status = "FAILED" if error else "DONE"
    ref.update({"status": status, "resultType": result_type,
                "resultId": result_id, "error": error})
    return {"captureId": capture_id, "status": status, "resultType": result_type,
            "resultId": result_id, "error": error}


def process_capture(business_id: str, source: str, capture_type: str, text: str | None = None,
                    file_bytes: bytes | None = None, zalo_message_id: str | None = None) -> dict:
    capture_id = new_id("cap")
    ref = business(business_id).collection("captures").document(capture_id)

    file_url = None
    if file_bytes:
        ext, content_type = _file_kind(capture_type, file_bytes)
        file_url = storage.upload(f"captures/{business_id}/{capture_id}.{ext}",
                                  file_bytes, content_type)
    ref.set({"captureId": capture_id, "source": source, "type": capture_type, "text": text,
             "transcript": None, "fileUrl": file_url, "zaloMessageId": zalo_message_id,
             "status": "PROCESSING", "resultType": None, "resultId": None, "error": None,
             "createdAt": now_iso()})

    transcript = None
    try:
        if capture_type == "TEXT":
            extraction = openai_client.extract_event(text=text)
        elif capture_type == "AUDIO":
            transcript = openai_client.transcribe(file_bytes)
            ref.update({"transcript": transcript})
            extraction = openai_client.extract_event(text=transcript)
        elif capture_type == "IMAGE_RECEIPT":
            extraction = openai_client.extract_event(image=file_bytes)
        elif capture_type == "IMAGE_TRANSFER":
            extraction = openai_client.extract_transfer(file_bytes)
        else:                                   # IMAGE_UNKNOWN — ảnh từ Zalo
            out = openai_client.extract_image(file_bytes)
            if out.kind == "RECEIPT" and out.event:
                extraction, capture_type = out.event, "IMAGE_RECEIPT"
            elif out.kind == "TRANSFER" and out.transfer:
                extraction, capture_type = out.transfer, "IMAGE_TRANSFER"
            else:
                return _result(ref, capture_id, error="UNRECOGNIZED_IMAGE")
            # Ghi lại type sau khi đã biết kind; không lưu IMAGE_UNKNOWN lên event/movement.
            ref.update({"type": capture_type})
    except Exception:
        logging.exception("AI lỗi khi xử lý capture %s", capture_id)
        return _result(ref, capture_id, error="AI_EXTRACTION_FAILED")

    is_image = capture_type.startswith("IMAGE_")
    ts = now_iso()                               # occurredAt = now(), không lấy từ AI
    common = {"source": source, "captureType": capture_type,
              "evidenceText": text or transcript, "evidenceUrl": file_url,
              "occurredAt": ts, "sourceCaptureId": capture_id, "createdAt": ts, "updatedAt": ts}

    if isinstance(extraction, openai_client.TransferExtraction):
        if extraction.amount <= 0:
            return _result(ref, capture_id, error="UNRECOGNIZED_IMAGE")
        movement_id = new_id("mov")
        business(business_id).collection("money_movements").document(movement_id).set({
            "movementId": movement_id, "direction": extraction.direction,
            "amount": extraction.amount, "memo": extraction.memo,
            "counterparty": extraction.counterparty, "status": "UNMATCHED",
            "matchedEventId": None, "classificationType": None, "classifiedAt": None, **common,
        })
        return _result(ref, capture_id, "MONEY_MOVEMENT", movement_id)

    if extraction.type == "UNKNOWN" and extraction.amount == 0:
        # Câu chào hỏi, ảnh nhãn sản phẩm… → không tạo draft rác (eval A4/R3).
        return _result(ref, capture_id,
                       error="UNRECOGNIZED_IMAGE" if is_image else "NO_TRANSACTION")

    event_id = new_id("ev")
    business(business_id).collection("events").document(event_id).set({
        "eventId": event_id, "type": extraction.type, "status": "DRAFT",
        "amount": extraction.amount, "description": extraction.description,
        "counterparty": extraction.counterparty, "paymentMethod": extraction.paymentMethod,
        "paymentStatus": extraction.paymentStatus, "confidence": extraction.confidence, **common,
    })
    return _result(ref, capture_id, "EVENT", event_id)
