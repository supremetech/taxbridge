import os

from firebase_functions import https_fn, options

from app.flask_app import create_app

app = create_app()   # create_app() gọi firebase_admin.initialize_app() có guard


@https_fn.on_request(
    region="asia-southeast1", timeout_sec=120, memory=options.MemoryOption.MB_512,
    min_instances=int(os.environ.get("MIN_INSTANCES", "0")),
    # ZALO_BOT_TOKEN: bot reply (§16). IAM `roles/secretmanager.secretAccessor` đã cấp cho
    # 495996584842-compute@developer.gserviceaccount.com ngày 12/09 → deploy được.
    secrets=[options.SecretParam(n)
             for n in ("OPENAI_API_KEY", "ZALO_WEBHOOK_SECRET", "ZALO_BOT_TOKEN")])
def api(req: https_fn.Request) -> https_fn.Response:
    with app.request_context(req.environ):
        return app.full_dispatch_request()
