#!/usr/bin/env bash
# Firestore emulator + Flask local, không cần ADC (gcloud auth).
# Storage không có trong emulator → `evidenceUrl` sẽ là null, capture vẫn DONE.
#
#   tests/smoke/emulator.sh            # chạy tới khi Ctrl-C
#   tests/smoke/emulator.sh smoke      # chạy xong smoke.sh rồi tắt
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export GCLOUD_PROJECT="${GCLOUD_PROJECT:-hackathon-42790}"
export FIRESTORE_EMULATOR_HOST="${FIRESTORE_EMULATOR_HOST:-localhost:8080}"
PORT="${PORT:-8787}"

cleanup() { kill $(jobs -p) 2>/dev/null || true; }
trap cleanup EXIT

(cd "$ROOT" && firebase emulators:start --only firestore --project "$GCLOUD_PROJECT") &
until curl -sS "http://$FIRESTORE_EMULATOR_HOST" > /dev/null 2>&1; do sleep 1; done
echo "firestore emulator: $FIRESTORE_EMULATOR_HOST"

(cd "$ROOT/functions" && flask --app app.flask_app:create_app run --port "$PORT") &
until curl -sS "http://localhost:$PORT/api/health" > /dev/null 2>&1; do sleep 1; done
echo "flask: http://localhost:$PORT"

if [ "${1:-}" = "smoke" ]; then
  BASE="http://localhost:$PORT" "$ROOT/tests/smoke/smoke.sh"
else
  wait
fi
