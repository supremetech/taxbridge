"""Zalo Bot Platform: normalize payload, tải media, remux voice, bot trả lời (contract §6)."""

import logging
import os
import subprocess
import tempfile
from datetime import datetime

import imageio_ffmpeg
import requests

from . import errors, event_service, reconciliation_service
from .capture_service import process_capture
from .config import ZALO_BOT_API
from .dashboard_service import money
from .firestore import TZ, db, now_iso

# Message đẩy được vào pipeline capture; còn lại (STICKER, OTHER) chỉ ghi nhận người gửi.
CAPTURE_TYPES = {"TEXT", "IMAGE", "AUDIO"}


def _sticker_url(msg: dict) -> str | None:
    """Zalo không công bố shape của `sticker`, nên đọc phòng thủ: dict, string, hay *_id đều nhận."""
    sticker = msg.get("sticker")
    if isinstance(sticker, str):
        return sticker
    if isinstance(sticker, dict):
        for key in ("url", "sticker_url", "image_url", "icon_url", "href"):
            if isinstance(sticker.get(key), str):
                return sticker[key]
        for key in ("id", "sticker_id"):
            if sticker.get(key) is not None:
                return str(sticker[key])
    for key in ("sticker_url", "sticker_id"):
        if msg.get(key) is not None:
            return str(msg[key])
    return None


def _message_type(msg: dict, event_name: str, sticker_url: str | None) -> str:
    """Suy từ field có mặt, không dựa vào `event_name` một mình (Zalo có thể thêm event mới)."""
    if msg.get("voice_url"):
        return "AUDIO"
    if msg.get("photo_url"):
        return "IMAGE"
    if (sticker_url is not None or "sticker" in msg
            or event_name.endswith("sticker.received")
            or msg.get("message_type") == "CHAT_STICKER"):
        return "STICKER"
    if msg.get("text"):
        return "TEXT"
    return "OTHER"


def normalize(payload: dict | None) -> dict | None:
    """Trả shape `fixtures/zalo/normalized_*.json`, hoặc None nếu không phải message của user.

    Nhận **mọi** message có người gửi, kể cả sticker hay loại chưa biết (`OTHER`): user phải
    được ghi nhận vào `zalo_users` thì mới hiện ở dropdown Register (UC8), dù message đầu tiên
    họ gửi không phải giao dịch.
    """
    msg = (payload or {}).get("message") or {}
    sender = msg.get("from") or {}
    zalo_id = sender.get("id")
    if not zalo_id:
        return None

    sticker_url = _sticker_url(msg)
    sent_at = now_iso()
    if isinstance(msg.get("date"), (int, float)):
        sent_at = datetime.fromtimestamp(msg["date"] / 1000, TZ).isoformat(timespec="seconds")

    return {"zaloId": zalo_id, "displayName": sender.get("display_name"),
            "chatId": (msg.get("chat") or {}).get("id") or zalo_id,
            "messageId": msg.get("message_id") or f"zm_{int(datetime.now().timestamp() * 1000)}",
            "messageType": _message_type(msg, (payload or {}).get("event_name") or "", sticker_url),
            "text": msg.get("text"), "imageUrl": msg.get("photo_url"),
            "audioUrl": msg.get("voice_url"), "stickerUrl": sticker_url,
            "sentAt": sent_at, "rawPayload": payload}


def download(url: str) -> bytes:
    """Media URL của Zalo public, GET thẳng không cần token; có thể hết hạn nên tải ngay."""
    resp = requests.get(url, timeout=30)
    resp.raise_for_status()
    return resp.content


def aac_to_m4a(aac_bytes: bytes) -> bytes:
    """Raw ADTS AAC → M4A, không re-encode. OpenAI không nhận .aac."""
    exe = imageio_ffmpeg.get_ffmpeg_exe()
    with tempfile.TemporaryDirectory() as d:
        src, dst = f"{d}/in.aac", f"{d}/out.m4a"
        with open(src, "wb") as f:
            f.write(aac_bytes)
        subprocess.run([exe, "-v", "error", "-y", "-i", src, "-c:a", "copy", dst], check=True)
        with open(dst, "rb") as f:
            return f.read()


# --- Bot trả lời (contract §6.1) ------------------------------------------

EVENT_LABELS = {"SALE": "Bán hàng", "PURCHASE": "Mua hàng", "DEPOSIT": "Đặt cọc",
                "OWNER_MONEY": "Tiền cá nhân", "UNKNOWN": "Giao dịch"}
PAYMENT_LABELS = {("BANK", "UNPAID"): "CK, chưa thu", ("BANK", "PAID"): "CK, đã thu",
                  ("CASH", "PAID"): "tiền mặt", ("CASH", "UNPAID"): "tiền mặt",
                  ("CASH", "UNKNOWN"): "tiền mặt"}


def reply(chat_id: str, text: str) -> None:
    """Gửi trong request webhook, trước khi trả 200. Không bao giờ raise."""
    token = os.environ.get("ZALO_BOT_TOKEN", "")
    if not token:
        logging.warning("ZALO_BOT_TOKEN rỗng — bỏ qua reply")
        return
    try:
        r = requests.post(ZALO_BOT_API.format(token=token, method="sendMessage"),
                          json={"chat_id": chat_id, "text": text}, timeout=10)
        logging.info("sendMessage → %s %s", r.status_code, r.text[:200])
    except Exception as e:
        logging.warning("sendMessage lỗi: %s", e)


def reply_text(result: dict | None, business_id: str | None, message: dict) -> str | None:
    """Câu trả lời theo kết quả capture; None = không trả lời (sticker / loại lạ)."""
    if result is None:
        if message["messageType"] not in CAPTURE_TYPES:
            return None
        name = message.get("displayName") or "tài khoản Zalo của bạn"
        return (f'TaxBridge chưa liên kết Zalo này. Mở app → Đăng ký → chọn "{name}" '
                f"ở mục Zalo account.")

    if result["status"] == "FAILED":
        return ('❌ Chưa đọc được giao dịch. Nhắn rõ hơn, ví dụ: '
                '"bán 3 hộp collagen 450 nghìn ck".')

    if result["resultType"] == "EVENT":
        event = event_service.get(business_id, result["resultId"])
        parts = [f"{EVENT_LABELS.get(event['type'], 'Giao dịch')} {money(event['amount'])}"]
        if event.get("counterparty"):
            parts.append(event["counterparty"])
        payment = PAYMENT_LABELS.get((event.get("paymentMethod"), event.get("paymentStatus")))
        if payment:
            parts.append(payment)
        return f"✅ Đã ghi nháp: {' · '.join(parts)}. Mở app để xác nhận."

    if result["resultType"] == "MONEY_MOVEMENT":
        movement = reconciliation_service.get_dto(business_id, result["resultId"])
        label = "Tiền vào" if movement["direction"] == "IN" else "Tiền ra"
        who = movement.get("counterparty") or movement.get("memo")
        head = f"🏦 {label} {money(movement['amount'])}" + (f" từ {who}" if who else "")
        n = len(movement["candidates"])
        if n:
            return f"{head} — có {n} đơn có thể khớp. Mở app để ghép."
        return f"{head} — chưa rõ là khoản gì. Mở app để phân loại."

    return None


def _upsert_user(message: dict) -> dict:
    ref = db.collection("zalo_users").document(message["zaloId"])
    doc = ref.get()
    ts = now_iso()
    if doc.exists:
        ref.update({"displayName": message["displayName"], "lastSeenAt": ts})
        return doc.to_dict()
    user = {"zaloId": message["zaloId"], "displayName": message["displayName"],
            "linkedAccountId": None, "linkedBusinessId": None,
            "firstSeenAt": ts, "lastSeenAt": ts}
    ref.set(user)
    return user


def _capture_message(business_id: str, message: dict) -> dict | None:
    """Đẩy một message Zalo vào pipeline capture. Sticker / loại lạ → None (§14)."""
    if message["messageType"] not in CAPTURE_TYPES:
        # Sticker / loại chưa biết: không có giao dịch để trích. Không gọi AI (tốn tiền, dễ ra
        # draft rác), không tạo capture. `lastSeenAt` đã cập nhật ở _upsert_user là đủ.
        logging.info("Zalo message %s loại %s — bỏ qua, không phải giao dịch",
                     message["messageId"], message["messageType"])
        return None

    if message["messageType"] == "TEXT":
        return process_capture(business_id, "ZALO", "TEXT", text=message["text"],
                               zalo_message_id=message["messageId"])
    if message["messageType"] == "IMAGE":
        return process_capture(business_id, "ZALO", "IMAGE_UNKNOWN",
                               file_bytes=download(message["imageUrl"]),
                               zalo_message_id=message["messageId"])
    return process_capture(business_id, "ZALO", "AUDIO",
                           file_bytes=aac_to_m4a(download(message["audioUrl"])),
                           zalo_message_id=message["messageId"])


def handle(payload: dict | None) -> None:
    """Webhook luôn trả 200; mọi lỗi nuốt tại đây (capture.error đã ghi trong pipeline)."""
    message = normalize(payload)
    if not message:
        return

    user = _upsert_user(message)
    business_id = user.get("linkedBusinessId")
    if not business_id:
        # Chưa link: lưu lại để hiện trong dropdown Register (UC8) và replay sau khi link (§14).
        db.collection("zalo_unlinked_messages").document(message["messageId"]).set(
            {**message, "receivedAt": now_iso(), "replayedAt": None})

    result = None
    if business_id:
        try:
            result = _capture_message(business_id, message)
        except Exception:
            logging.exception("xử lý message Zalo %s lỗi", message["messageId"])
            result = {"status": "FAILED", "resultType": None, "resultId": None}

    # Trả lời trong chính request webhook, trước khi trả 200 (CPU đóng băng sau response).
    try:
        text = reply_text(result, business_id, message)
    except Exception:
        logging.exception("dựng câu trả lời cho %s lỗi", message["messageId"])
        text = None
    if text:
        reply(message["chatId"], text)


def replay(account_id: str, business_id: str, zalo_id: str) -> dict:
    """Xử lý lại message gửi TRƯỚC khi link (contract §6.2). Không bot reply khi replay."""
    user = db.collection("zalo_users").document(zalo_id).get()
    if not user.exists or user.to_dict().get("linkedAccountId") != account_id:
        raise errors.not_found("Zalo user chưa liên kết với tài khoản này.")

    # Đọc cả collection rồi lọc trong Python: tránh composite index (CLAUDE.md §6).
    messages = [(d.reference, d.to_dict()) for d in
                db.collection("zalo_unlinked_messages").stream()]
    messages = [(ref, m) for ref, m in messages
                if m.get("zaloId") == zalo_id and not m.get("replayedAt")]
    messages.sort(key=lambda item: item[1].get("sentAt") or "")

    done = failed = skipped = 0
    for ref, message in messages:
        try:
            result = _capture_message(business_id, message)
        except Exception:          # media URL Zalo hết hạn, AI lỗi…
            logging.exception("replay message Zalo %s lỗi", message.get("messageId"))
            result = {"status": "FAILED"}
        if result is None:
            skipped += 1
        elif result["status"] == "DONE":
            done += 1
        else:
            failed += 1
        ref.update({"replayedAt": now_iso()})   # kể cả failed: không thử lại

    return {"zaloId": zalo_id, "replayed": done + failed,
            "done": done, "failed": failed, "skipped": skipped}
