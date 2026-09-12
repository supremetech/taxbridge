#!/usr/bin/env bash
# Smoke 9 UC (CLAUDE.md §9) + Zalo simulator. Cần `curl` và `jq`.
#
#   BASE=http://localhost:8787 tests/smoke/smoke.sh
#   BASE=https://asia-southeast1-hackathon-42790.cloudfunctions.net/api tests/smoke/smoke.sh
#
# Biến môi trường:
#   BASE                 URL gốc (mặc định http://localhost:8787)
#   PROMPT_DIR           repo taxbridge-prompt (mặc định ../taxbridge-prompt)
#   ZALO_WEBHOOK_SECRET  gửi kèm header X-Bot-Api-Secret-Token
#   ZALO_MEDIA=1         chạy thêm UC9 ảnh/voice (media URL thật trong fixture, dễ hết hạn)
set -uo pipefail

B="${BASE:-http://localhost:8787}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
P="${PROMPT_DIR:-$ROOT/../taxbridge-prompt}"
FX="$P/contract/fixtures"
ASSETS="$P/demo-assets"
D="$(TZ=Asia/Ho_Chi_Minh date +%F)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

command -v jq >/dev/null || { echo "cần jq"; exit 1; }
[ -d "$FX" ] || { echo "không thấy fixtures ở $FX (đặt PROMPT_DIR)"; exit 1; }

PASS=0; FAIL=0
uc()   { printf '\n\033[1m%s\033[0m\n' "$*"; }
ok()   { printf '  ✅ %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  ❌ %s — got: %s\n' "$1" "$2"; FAIL=$((FAIL+1)); }
eq()   { [ "$2" = "$3" ] && ok "$1 = $3" || bad "$1 = $3" "$2"; }
has()  { [ -n "$2" ] && [ "$2" != "null" ] && ok "$1" || bad "$1" "$2"; }

T=""
api()  { local m=$1 p=$2; shift 2; curl -sS -X "$m" "$B$p" -H "X-Session-Token: $T" "$@"; }
jpost(){ api POST "$1" -H 'Content-Type: application/json' -d "$2"; }
code() { local m=$1 p=$2; shift 2; curl -sS -o /dev/null -w '%{http_code}' -X "$m" "$B$p" \
           -H "X-Session-Token: $T" "$@"; }
dash() { api GET "/api/dashboard?date=$D" > "$TMP/dash.json"; jq -r ".$1" "$TMP/dash.json"; }
zalo() { curl -sS -X POST "$B/api/zalo/webhook" \
           -H "X-Bot-Api-Secret-Token: ${ZALO_WEBHOOK_SECRET:-}" \
           -H 'Content-Type: application/json' -d @"$1"; }

# ---------------------------------------------------------------- health + UC1
uc "UC1 · register"
eq "health" "$(curl -sS "$B/api/health" | jq -r .ok)" "true"

U="smoke_$(date +%s)_$RANDOM"
jpost /api/register "{\"username\":\"$U\",\"password\":\"123456\"}" > "$TMP/session.json"
T="$(jq -r .token "$TMP/session.json")"
has "session.token" "$T"
has "session.businessId" "$(jq -r .businessId "$TMP/session.json")"
eq "session.username" "$(jq -r .username "$TMP/session.json")" "$U"
eq "register trùng username → 409" \
   "$(code POST /api/register -H 'Content-Type: application/json' \
        -d "{\"username\":\"$U\",\"password\":\"123456\"}")" "409"

# --------------------------------------------------------------------- UC2 text
uc "UC2 · text → SALE draft → PUT → confirm"
jpost /api/captures "$(cat "$FX/capture_text_request.json")" > "$TMP/cap2.json"
eq "capture.status" "$(jq -r .status "$TMP/cap2.json")" "DONE"
eq "capture.resultType" "$(jq -r .resultType "$TMP/cap2.json")" "EVENT"
EV1="$(jq -r .resultId "$TMP/cap2.json")"

api GET "/api/events/$EV1" > "$TMP/ev1.json"
eq "event.type"          "$(jq -r .type "$TMP/ev1.json")" "SALE"
eq "event.status"        "$(jq -r .status "$TMP/ev1.json")" "DRAFT"
eq "event.amount (eval)" "$(jq -r .amount "$TMP/ev1.json")" "450000"
eq "event.paymentMethod" "$(jq -r .paymentMethod "$TMP/ev1.json")" "BANK"
eq "event.paymentStatus" "$(jq -r .paymentStatus "$TMP/ev1.json")" "UNPAID"
eq "event.source"        "$(jq -r .source "$TMP/ev1.json")" "APP"
eq "event.captureType"   "$(jq -r .captureType "$TMP/ev1.json")" "TEXT"
eq "event.evidenceText"  "$(jq -r .evidenceText "$TMP/ev1.json")" "$(jq -r .text "$FX/capture_text_request.json")"
eq "event.evidenceUrl"   "$(jq -r .evidenceUrl "$TMP/ev1.json")" "null"
eq "event.occurredAt hôm nay" "$(jq -r '.occurredAt[:10]' "$TMP/ev1.json")" "$D"

api PUT "/api/events/$EV1" -H 'Content-Type: application/json' \
    -d '{"counterparty":"chị Lan"}' > "$TMP/ev1.json"
eq "PUT counterparty" "$(jq -r .counterparty "$TMP/ev1.json")" "chị Lan"
eq "PUT field lạ → 400" "$(code PUT "/api/events/$EV1" -H 'Content-Type: application/json' \
    -d '{"evidenceUrl":"x"}')" "400"

api POST "/api/events/$EV1/confirm" > "$TMP/ev1.json"
eq "confirm → status"   "$(jq -r .status "$TMP/ev1.json")" "CONFIRMED"
eq "confirm giữ UNPAID" "$(jq -r .paymentStatus "$TMP/ev1.json")" "UNPAID"
eq "confirm lại → 409"  "$(code POST "/api/events/$EV1/confirm")" "409"
eq "dashboard.revenue"    "$(dash revenue)" "450000"
eq "dashboard.receivable" "$(dash receivable)" "450000"
eq "dashboard.collected"  "$(dash collected)" "0"
eq "dashboard.draftCount" "$(dash draftCount)" "0"

# -------------------------------------------------------------------- UC3 voice
uc "UC3 · voice (sale_voice.m4a) → SALE draft → confirm"
api POST /api/captures -F type=AUDIO -F "file=@$ASSETS/sale_voice.m4a" > "$TMP/cap3.json"
eq "capture.status" "$(jq -r .status "$TMP/cap3.json")" "DONE"
EV2="$(jq -r .resultId "$TMP/cap3.json")"
api GET "/api/events/$EV2" > "$TMP/ev2.json"
eq "event.type"          "$(jq -r .type "$TMP/ev2.json")" "SALE"
eq "event.amount (eval)" "$(jq -r .amount "$TMP/ev2.json")" "450000"
eq "event.captureType"   "$(jq -r .captureType "$TMP/ev2.json")" "AUDIO"
has "event.evidenceText = transcript" "$(jq -r .evidenceText "$TMP/ev2.json")"
api POST "/api/events/$EV2/confirm" > /dev/null
eq "dashboard.revenue" "$(dash revenue)" "900000"

# ------------------------------------------------------------ UC4 transfer match
uc "UC4 · ảnh chuyển khoản 450k → candidate → match"
api POST /api/captures -F type=IMAGE_TRANSFER -F "file=@$ASSETS/transfer_match.jpg" > "$TMP/cap4.json"
eq "capture.resultType" "$(jq -r .resultType "$TMP/cap4.json")" "MONEY_MOVEMENT"
M1="$(jq -r .resultId "$TMP/cap4.json")"
api GET "/api/money-movements/$M1" > "$TMP/m1.json"
eq "movement.direction"    "$(jq -r .direction "$TMP/m1.json")" "IN"
eq "movement.amount (eval)" "$(jq -r .amount "$TMP/m1.json")" "450000"
eq "movement.status"       "$(jq -r .status "$TMP/m1.json")" "UNMATCHED"
eq "movement.captureType"  "$(jq -r .captureType "$TMP/m1.json")" "IMAGE_TRANSFER"
eq "candidate chứa event UC2" \
   "$(jq -r --arg e "$EV1" 'any(.candidates[]; .eventId == $e)' "$TMP/m1.json")" "true"
eq "candidate score >= 0.9" \
   "$(jq -r --arg e "$EV1" '[.candidates[] | select(.eventId==$e) | .score >= 0.9][0]' "$TMP/m1.json")" "true"
eq "dashboard.bankIn" "$(dash bankIn)" "450000"
eq "dashboard.unmatchedMoneyCount" "$(dash unmatchedMoneyCount)" "1"

URL="$(jq -r .evidenceUrl "$TMP/m1.json")"
if [ "$URL" = "null" ]; then
  printf '  ⚠️  evidenceUrl null (Storage không khả dụng — OK trên emulator)\n'
else
  eq "evidenceUrl mở được" "$(curl -sS -o /dev/null -w '%{http_code}' "$URL")" "200"
fi

jpost "/api/money-movements/$M1/match" "{\"eventId\":\"$EV1\"}" > "$TMP/m1.json"
eq "match → status"         "$(jq -r .status "$TMP/m1.json")" "MATCHED"
eq "match → matchedEventId" "$(jq -r .matchedEventId "$TMP/m1.json")" "$EV1"
eq "match → candidates rỗng" "$(jq -r '.candidates | length' "$TMP/m1.json")" "0"
eq "event → PAID" "$(api GET "/api/events/$EV1" | jq -r .paymentStatus)" "PAID"
eq "match lại → 409" "$(code POST "/api/money-movements/$M1/match" \
    -H 'Content-Type: application/json' -d "{\"eventId\":\"$EV1\"}")" "409"
eq "dashboard.collected"  "$(dash collected)" "450000"
eq "dashboard.receivable" "$(dash receivable)" "450000"

# ------------------------------------------------- UC5 transfer classify (hero)
uc "UC5 · ảnh chuyển khoản 380k → không candidate → classify DEPOSIT (hero)"
api POST /api/captures -F type=IMAGE_TRANSFER -F "file=@$ASSETS/transfer_deposit.jpg" > "$TMP/cap5.json"
M2="$(jq -r .resultId "$TMP/cap5.json")"
api GET "/api/money-movements/$M2" > "$TMP/m2.json"
eq "movement.amount (eval)" "$(jq -r .amount "$TMP/m2.json")" "380000"
eq "candidates rỗng (hero)" "$(jq -r '.candidates | length' "$TMP/m2.json")" "0"
eq "dashboard.bankIn" "$(dash bankIn)" "830000"
REV_BEFORE="$(dash revenue)"

jpost "/api/money-movements/$M2/classify" "$(cat "$FX/classify_request.json")" > "$TMP/m2.json"
eq "classify → status" "$(jq -r .status "$TMP/m2.json")" "CLASSIFIED"
eq "classify → classificationType" "$(jq -r .classificationType "$TMP/m2.json")" "DEPOSIT"
eq "revenue KHÔNG đổi (hero)" "$(dash revenue)" "$REV_BEFORE"
eq "bankIn giữ nguyên (hero)" "$(dash bankIn)" "830000"
eq "unmatchedMoneyCount" "$(dash unmatchedMoneyCount)" "0"

# ------------------------------------------------------------- UC6 ảnh phiếu thu
uc "UC6 · ảnh phiếu mua 220k → PURCHASE draft → confirm"
api POST /api/captures -F type=IMAGE_RECEIPT -F "file=@$ASSETS/receipt.jpg" > "$TMP/cap6.json"
EV3="$(jq -r .resultId "$TMP/cap6.json")"
api GET "/api/events/$EV3" > "$TMP/ev3.json"
eq "event.type (eval)"   "$(jq -r .type "$TMP/ev3.json")" "PURCHASE"
eq "event.amount (eval)" "$(jq -r .amount "$TMP/ev3.json")" "220000"
eq "event.captureType"   "$(jq -r .captureType "$TMP/ev3.json")" "IMAGE_RECEIPT"
api POST "/api/events/$EV3/confirm" > /dev/null
eq "dashboard.expense" "$(dash expense)" "220000"

# ------------------------------------------------------ UC7 close day + warning
uc "UC7 · đóng ngày → warning → xử lý → RESOLVED"
jpost /api/captures '{"type":"TEXT","text":"Mua túi giấy 180 nghìn tiền mặt"}' > "$TMP/cap7.json"
EV4="$(jq -r .resultId "$TMP/cap7.json")"
eq "còn 1 draft" "$(dash draftCount)" "1"

jpost /api/close-day "{\"date\":\"$D\"}" > "$TMP/rec.json"
eq "record.date"         "$(jq -r .date "$TMP/rec.json")" "$D"
eq "record.warningCount" "$(jq -r .warningCount "$TMP/rec.json")" "1"
eq "warning DRAFT_EVENT" "$(jq -r --arg e "$EV4" \
   'any(.warnings[]; .warningId == "DRAFT_EVENT:\($e)" and .status == "OPEN")' "$TMP/rec.json")" "true"
has "record.closedAt" "$(jq -r .closedAt "$TMP/rec.json")"
eq "summary.revenue" "$(jq -r .summary.revenue "$TMP/rec.json")" "900000"

api POST "/api/events/$EV4/confirm" > /dev/null
api GET "/api/daily-records/$D" > "$TMP/rec.json"
eq "warning → RESOLVED"  "$(jq -r --arg e "$EV4" \
   '.warnings[] | select(.warningId == "DRAFT_EVENT:\($e)") | .status' "$TMP/rec.json")" "RESOLVED"
has "warning.resolvedAt" "$(jq -r --arg e "$EV4" \
   '.warnings[] | select(.warningId == "DRAFT_EVENT:\($e)") | .resolvedAt' "$TMP/rec.json")"
eq "record.warningCount" "$(jq -r .warningCount "$TMP/rec.json")" "0"
eq "summary.expense recompute" "$(jq -r .summary.expense "$TMP/rec.json")" "400000"
eq "daily-records list" "$(api GET /api/daily-records | jq -r 'length >= 1')" "true"

# ------------------------------------------------------------ UC8 Zalo chưa link
uc "UC8 · Zalo user chưa link nhắn bot"
ZID="$(LC_ALL=C tr -dc 'a-f0-9' < /dev/urandom | head -c 20)"
jq --arg id "$ZID" --arg m "m${ZID}1" \
   '.message.from.id=$id | .message.chat.id=$id | .message.message_id=$m' \
   "$FX/zalo/webhook_text.json" > "$TMP/wh_text.json"
eq "webhook → ok" "$(zalo "$TMP/wh_text.json" | jq -r .ok)" "true"
eq "body rỗng (probe) → 200" \
   "$(curl -sS -o /dev/null -w '%{http_code}' -X POST "$B/api/zalo/webhook" \
      -H "X-Bot-Api-Secret-Token: ${ZALO_WEBHOOK_SECRET:-}")" "200"
eq "user trong /zalo-users/unlinked" \
   "$(curl -sS "$B/api/zalo-users/unlinked" | jq -r --arg id "$ZID" 'any(.[]; .zaloId == $id)')" "true"

# ------------------------------------------------------------- UC9 Zalo đã link
uc "UC9 · Zalo user đã link nhắn bot"
U2="${U}_zalo"
jpost /api/register "{\"username\":\"$U2\",\"password\":\"123456\",\"zaloId\":\"$ZID\"}" > "$TMP/s2.json"
T="$(jq -r .token "$TMP/s2.json")"
has "session 2" "$T"
eq "zaloId đã link → 409" "$(code POST /api/register -H 'Content-Type: application/json' \
    -d "{\"username\":\"${U2}_x\",\"password\":\"123456\",\"zaloId\":\"$ZID\"}")" "409"
eq "hết trong unlinked" \
   "$(curl -sS "$B/api/zalo-users/unlinked" | jq -r --arg id "$ZID" 'any(.[]; .zaloId == $id)')" "false"

jq --arg m "m${ZID}2" '.message.message_id=$m' "$TMP/wh_text.json" > "$TMP/wh_text2.json"
zalo "$TMP/wh_text2.json" > /dev/null
api GET "/api/events?status=DRAFT" > "$TMP/zev.json"
eq "có draft từ Zalo" "$(jq -r 'length >= 1' "$TMP/zev.json")" "true"
eq "draft.source"      "$(jq -r '.[0].source' "$TMP/zev.json")" "ZALO"
eq "draft.captureType" "$(jq -r '.[0].captureType' "$TMP/zev.json")" "TEXT"

if [ "${ZALO_MEDIA:-0}" = "1" ]; then
  jq --arg id "$ZID" --arg m "m${ZID}3" \
     '.message.from.id=$id | .message.chat.id=$id | .message.message_id=$m' \
     "$FX/zalo/webhook_image.json" > "$TMP/wh_img.json"
  jq --arg id "$ZID" --arg m "m${ZID}4" \
     '.message.from.id=$id | .message.chat.id=$id | .message.message_id=$m' \
     "$FX/zalo/webhook_voice.json" > "$TMP/wh_voice.json"
  eq "webhook ảnh → ok"  "$(zalo "$TMP/wh_img.json" | jq -r .ok)" "true"
  eq "webhook voice → ok" "$(zalo "$TMP/wh_voice.json" | jq -r .ok)" "true"
  # Media trong fixture là ảnh/voice test ngày 10/09, KHÔNG chứa giao dịch: ảnh → kind=OTHER
  # (UNRECOGNIZED_IMAGE), voice transcribe ra "Chào anh Tuấn, lộ." → NO_TRANSACTION.
  # Đúng kỳ vọng: capture FAILED, không sinh draft rác → không assert có event mới.
  printf '  ℹ️  media fixture không chứa giao dịch → capture FAILED, không tạo draft (đã xác minh 12/09)\n'
else
  printf '  ⚠️  bỏ qua Zalo ảnh/voice (đặt ZALO_MEDIA=1 khi media URL còn sống)\n'
fi

# ------------------------------------------------------------------- contract
uc "Contract"
eq "/api/docs public → 200"        "$(code GET /api/docs)" "200"
eq "/api/openapi.yaml public → 200" "$(code GET /api/openapi.yaml)" "200"
eq "spec có đủ path"  "$(curl -sS "$B/api/openapi.yaml" | grep -c '^  /api/')" "21"

SAVED="$T"; T="tb_sai"
eq "token sai → 401" "$(code GET /api/events)" "401"
T="$SAVED"
eq "logout → 204" "$(code POST /api/logout)" "204"
eq "token đã logout → 401" "$(code GET /api/events)" "401"

printf '\n\033[1m%s pass · %s fail\033[0m\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
