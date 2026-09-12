"""Zalo Bot Platform: normalize payload, tải media, remux voice (contract/README §6)."""

import logging
import subprocess
import tempfile
from datetime import datetime

import imageio_ffmpeg
import requests

from .capture_service import process_capture
from .firestore import TZ, db, now_iso


def normalize(payload: dict | None) -> dict | None:
    """Trả shape `fixtures/zalo/normalized_*.json`, hoặc None nếu không phải message xử lý được."""
    msg = (payload or {}).get("message") or {}
    sender = msg.get("from") or {}
    zalo_id = sender.get("id")
    text, photo_url, voice_url = msg.get("text"), msg.get("photo_url"), msg.get("voice_url")
    if not zalo_id or not (text or photo_url or voice_url):
        return None

    # Suy messageType từ field có mặt, không dựa vào event_name.
    message_type = "AUDIO" if voice_url else "IMAGE" if photo_url else "TEXT"
    sent_at = now_iso()
    if isinstance(msg.get("date"), (int, float)):
        sent_at = datetime.fromtimestamp(msg["date"] / 1000, TZ).isoformat(timespec="seconds")

    return {"zaloId": zalo_id, "displayName": sender.get("display_name"),
            "chatId": (msg.get("chat") or {}).get("id") or zalo_id,
            "messageId": msg.get("message_id") or f"zm_{int(datetime.now().timestamp() * 1000)}",
            "messageType": message_type, "text": text, "imageUrl": photo_url,
            "audioUrl": voice_url, "sentAt": sent_at, "rawPayload": payload}


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


def handle(payload: dict | None) -> None:
    """Webhook luôn trả 200; mọi lỗi nuốt tại đây (capture.error đã ghi trong pipeline)."""
    message = normalize(payload)
    if not message:
        return

    user = _upsert_user(message)
    business_id = user.get("linkedBusinessId")
    if not business_id:
        # Chưa link: lưu lại để hiện trong dropdown Register (UC8). Không xử lý lại sau khi link.
        db.collection("zalo_unlinked_messages").document(message["messageId"]).set(
            {**message, "receivedAt": now_iso()})
        return

    try:
        if message["messageType"] == "TEXT":
            process_capture(business_id, "ZALO", "TEXT", text=message["text"],
                            zalo_message_id=message["messageId"])
        elif message["messageType"] == "IMAGE":
            process_capture(business_id, "ZALO", "IMAGE_UNKNOWN",
                            file_bytes=download(message["imageUrl"]),
                            zalo_message_id=message["messageId"])
        else:
            process_capture(business_id, "ZALO", "AUDIO",
                            file_bytes=aac_to_m4a(download(message["audioUrl"])),
                            zalo_message_id=message["messageId"])
    except Exception:
        logging.exception("xử lý message Zalo %s lỗi", message["messageId"])
