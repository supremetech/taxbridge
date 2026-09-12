"""Swagger UI + OpenAPI spec.

Spec viết tay ở `app/openapi.yaml` (không thêm thư viện sinh spec — CLAUDE.md §10.3).
Swagger UI lấy từ CDN nên không có asset nào phải deploy kèm.
"""

from pathlib import Path

from flask import Response

from . import bp

SPEC = Path(__file__).resolve().parent.parent / "openapi.yaml"
SWAGGER_VERSION = "5.17.14"

# `url: "openapi.yaml"` là đường dẫn tương đối nên chạy đúng ở cả hai nơi:
# local  /api/docs          → /api/openapi.yaml
# prod   /api/api/docs      → /api/api/openapi.yaml  (function name + path, CLAUDE.md §8)
PAGE = f"""<!doctype html>
<html lang="vi">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>TaxBridge API</title>
  <link rel="stylesheet"
        href="https://cdn.jsdelivr.net/npm/swagger-ui-dist@{SWAGGER_VERSION}/swagger-ui.css">
</head>
<body>
  <div id="swagger-ui"></div>
  <script src="https://cdn.jsdelivr.net/npm/swagger-ui-dist@{SWAGGER_VERSION}/swagger-ui-bundle.js"></script>
  <script>
    window.ui = SwaggerUIBundle({{
      url: "openapi.yaml",
      dom_id: "#swagger-ui",
      deepLinking: true,
      persistAuthorization: true,
      tryItOutEnabled: true
    }});
  </script>
</body>
</html>
"""


@bp.get("/openapi.yaml")
def openapi_spec():
    return Response(SPEC.read_text(encoding="utf-8"), mimetype="application/yaml")


@bp.get("/docs")
def swagger_ui():
    return Response(PAGE, mimetype="text/html")
