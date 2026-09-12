"""Hằng số cấu hình PoC: model OpenAI, giới hạn file, ngưỡng chấm candidate."""

# --- OpenAI ---------------------------------------------------------------
# Pin theo CLAUDE.md §6. Fallback dùng khi model chính ném exception (thử lại 1 lần).
VISION_MODEL = "gpt-5.6-terra"
VISION_FALLBACK_MODEL = "gpt-5.6-luna"
REASONING_EFFORT = "low"
TRANSCRIBE_MODEL = "gpt-transcribe"
TRANSCRIBE_FALLBACK_MODEL = "gpt-4o-transcribe"

# --- Zalo Bot Platform ----------------------------------------------------
ZALO_BOT_API = "https://bot-api.zapps.me/bot{token}/{method}"

# --- Upload ---------------------------------------------------------------
MAX_FILE_BYTES = 10 * 1024 * 1024
MAX_AUDIO_SECONDS = 60
IMAGE_CONTENT_TYPES = {"image/jpeg": "jpg", "image/jpg": "jpg", "image/png": "png"}
AUDIO_CONTENT_TYPES = {"audio/mp4": "m4a", "audio/m4a": "m4a", "audio/x-m4a": "m4a"}

# --- Đối soát tiền vào ----------------------------------------------------
CANDIDATE_MIN_SCORE = 0.3   # "cùng ngày" (0.1) một mình không đủ để thành candidate
MAX_CANDIDATES = 3

# --- Thời gian ------------------------------------------------------------
TZ_NAME = "Asia/Ho_Chi_Minh"
