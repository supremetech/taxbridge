"""Upload Cloud Storage, trả download URL có token.

Không dùng signed URL (Functions cần quyền ký blob). URL public với ai có link — chấp
nhận trong PoC (contract §5.1).
"""

import logging
import uuid
from urllib.parse import quote

from firebase_admin import storage


def upload(path: str, data: bytes, content_type: str) -> str | None:
    try:
        bucket = storage.bucket()
        blob = bucket.blob(path)
        token = uuid.uuid4().hex
        blob.metadata = {"firebaseStorageDownloadTokens": token}
        blob.upload_from_string(data, content_type=content_type)
        return (f"https://firebasestorage.googleapis.com/v0/b/{bucket.name}"
                f"/o/{quote(path, safe='')}?alt=media&token={token}")
    except Exception as e:                  # emulator local không có Storage
        logging.warning("storage upload lỗi: %s", e)
        return None
