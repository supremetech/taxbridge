"""create_app(): initialize_app có guard, load .env, resolve session, đăng ký blueprint."""

import logging
import os
from pathlib import Path

import firebase_admin
from dotenv import load_dotenv
from flask import Flask, g, jsonify, request
from werkzeug.exceptions import HTTPException

from .config import MAX_FILE_BYTES
from .errors import ApiError
from .firestore import db

# Public: không cần X-Session-Token (contract §2).
PUBLIC = {"/api/health", "/api/register", "/api/login",
          "/api/zalo-users/unlinked", "/api/zalo/webhook",
          "/api/docs", "/api/openapi.yaml"}

HTTP_CODES = {400: "VALIDATION_ERROR", 401: "UNAUTHORIZED", 404: "NOT_FOUND",
              405: "VALIDATION_ERROR", 413: "FILE_TOO_LARGE", 415: "UNSUPPORTED_FILE_TYPE"}


def _init_firebase():
    if firebase_admin._apps:
        return
    if os.environ.get("FIREBASE_CONFIG"):        # trên Functions: tự resolve project + bucket
        firebase_admin.initialize_app()
        return

    project = os.environ.get("GCLOUD_PROJECT") or os.environ.get("GOOGLE_CLOUD_PROJECT")
    options = {"projectId": project, "storageBucket": f"{project}.firebasestorage.app"} \
        if project else {}
    credential = None
    if os.environ.get("FIRESTORE_EMULATOR_HOST"):
        from firebase_admin import credentials
        from google.auth.credentials import AnonymousCredentials

        class _Emulator(credentials.Base):       # emulator: không cần ADC
            def get_credential(self):
                return AnonymousCredentials()

        credential = _Emulator()
    firebase_admin.initialize_app(credential, options)


def create_app() -> Flask:
    # INFO để thấy log `sendMessage → …` khi chạy local (Functions đã bắt INFO sẵn).
    logging.basicConfig(level=logging.INFO)

    root = Path(__file__).resolve().parents[2]   # taxbridge-server/
    load_dotenv(root / ".env")                   # dev local; không tạo functions/.env
    load_dotenv(root / "functions" / ".env.local")

    _init_firebase()

    app = Flask(__name__)
    app.config["MAX_CONTENT_LENGTH"] = MAX_FILE_BYTES + 1024 * 1024

    @app.before_request
    def load_session():
        if request.path in PUBLIC:
            return None
        # Prod: Cloud Run chặn `Authorization: Bearer` lạ → app dùng X-Session-Token.
        token = (request.headers.get("X-Session-Token")
                 or request.headers.get("Authorization", "").removeprefix("Bearer ")).strip()
        doc = db.collection("sessions").document(token).get() if token else None
        if not doc or not doc.exists:
            return jsonify({"code": "UNAUTHORIZED", "message": "Token không hợp lệ."}), 401
        g.token = token
        g.account_id, g.business_id = doc.get("accountId"), doc.get("businessId")

    @app.errorhandler(ApiError)
    def _api_error(e: ApiError):
        return jsonify({"code": e.code, "message": e.message}), e.status

    @app.errorhandler(HTTPException)
    def _http_error(e: HTTPException):
        return jsonify({"code": HTTP_CODES.get(e.code, "INTERNAL_ERROR"),
                        "message": e.description}), e.code

    @app.errorhandler(Exception)
    def _unexpected(e: Exception):
        logging.exception("lỗi không mong đợi")
        return jsonify({"code": "INTERNAL_ERROR", "message": "Có lỗi xảy ra."}), 500

    from .routes import bp
    app.register_blueprint(bp)
    return app
