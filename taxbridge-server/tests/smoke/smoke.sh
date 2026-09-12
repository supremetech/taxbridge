#!/usr/bin/env bash
# Smoke 14 UC (CLAUDE.md §9 + Phase 2 UC10–14) + Zalo simulator. Cần `curl` và `jq`.
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
DOC="2026-09-11"        # ngày IN TRÊN 3 ảnh demo → occurredAt của bản ghi từ ảnh (Phase 2 ②)
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
dash()  { api GET "/api/dashboard?date=$D" > "$TMP/dash.json"; jq -r ".$1" "$TMP/dash.json"; }
dashd() { api GET "/api/dashboard?date=$2" > "$TMP/dashd.json"; jq -r ".$1" "$TMP/dashd.json"; }
zalo() { curl -sS -X POST "$B/api/zalo/webhook" \
           -H "X-Bot-Api-Secret-Token: ${ZALO_WEBHOOK_SECRET:-}" \
           -H 'Content-Type: application/json' -d @"$1"; }

# ---------------------------------------------------------------- health + UC1
uc "UC1 · register"
eq "health" "$(curl -sS "$B/api/health" | jq -r .ok)" "true"

U="smoke_$(date +%s)_$RANDOM"
jpost /api/register "{\"username\":\"$U\",\"password\":\"123456\"}" > "$TMP/session.json"
T="$(jq -r .token "$TMP/session.json")"
T1="$T"                 # UC9 đổi $T sang account 2 → UC10–14 quay lại business này
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
eq "capture.occurredAt hôm nay" "$(jq -r '.occurredAt[:10]' "$TMP/cap2.json")" "$D"
eq "capture.resultIds rỗng" "$(jq -r '.resultIds | length' "$TMP/cap2.json")" "0"
eq "capture.skippedCount" "$(jq -r .skippedCount "$TMP/cap2.json")" "0"
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
eq "movement.occurredAt = ngày trên ảnh (②)" "$(jq -r '.occurredAt[:10]' "$TMP/m1.json")" "$DOC"
eq "dashboard($DOC).bankIn" "$(dashd bankIn "$DOC")" "450000"
eq "dashboard($DOC).unmatchedMoneyCount" "$(dashd unmatchedMoneyCount "$DOC")" "1"

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
eq "tồn đọng ngày cũ hiện ở hôm nay (③)" "$(dash pastUnmatchedCount)" "0"

# ------------------------------------------------- UC5 transfer classify (hero)
uc "UC5 · ảnh chuyển khoản 380k → không candidate → classify DEPOSIT (hero)"
api POST /api/captures -F type=IMAGE_TRANSFER -F "file=@$ASSETS/transfer_deposit.jpg" > "$TMP/cap5.json"
M2="$(jq -r .resultId "$TMP/cap5.json")"
api GET "/api/money-movements/$M2" > "$TMP/m2.json"
eq "movement.amount (eval)" "$(jq -r .amount "$TMP/m2.json")" "380000"
eq "candidates rỗng (hero)" "$(jq -r '.candidates | length' "$TMP/m2.json")" "0"
eq "dashboard($DOC).bankIn" "$(dashd bankIn "$DOC")" "830000"
REV_BEFORE="$(dash revenue)"

jpost "/api/money-movements/$M2/classify" "$(cat "$FX/classify_request.json")" > "$TMP/m2.json"
eq "classify → status" "$(jq -r .status "$TMP/m2.json")" "CLASSIFIED"
eq "classify → classificationType" "$(jq -r .classificationType "$TMP/m2.json")" "DEPOSIT"
eq "revenue KHÔNG đổi (hero)" "$(dash revenue)" "$REV_BEFORE"
eq "bankIn giữ nguyên (hero)" "$(dashd bankIn "$DOC")" "830000"
eq "unmatchedMoneyCount" "$(dashd unmatchedMoneyCount "$DOC")" "0"

# ------------------------------------------------------------- UC6 ảnh phiếu thu
uc "UC6 · ảnh phiếu mua 220k → PURCHASE draft → confirm"
api POST /api/captures -F type=IMAGE_RECEIPT -F "file=@$ASSETS/receipt.jpg" > "$TMP/cap6.json"
EV3="$(jq -r .resultId "$TMP/cap6.json")"
api GET "/api/events/$EV3" > "$TMP/ev3.json"
eq "event.type (eval)"   "$(jq -r .type "$TMP/ev3.json")" "PURCHASE"
eq "event.amount (eval)" "$(jq -r .amount "$TMP/ev3.json")" "220000"
eq "event.captureType"   "$(jq -r .captureType "$TMP/ev3.json")" "IMAGE_RECEIPT"
eq "event.occurredAt = ngày trên phiếu (②)" "$(jq -r '.occurredAt[:10]' "$TMP/ev3.json")" "$DOC"
api POST "/api/events/$EV3/confirm" > /dev/null
eq "dashboard($DOC).expense" "$(dashd expense "$DOC")" "220000"

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
eq "summary.expense recompute" "$(jq -r .summary.expense "$TMP/rec.json")" "180000"
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

# Sticker: không phải giao dịch, nhưng user gửi sticker TRƯỚC vẫn phải hiện ở dropdown Register.
ZID2="$(LC_ALL=C tr -dc 'a-f0-9' < /dev/urandom | head -c 20)"
jq --arg id "$ZID2" --arg m "s${ZID2}1" \
   '.message.from.id=$id | .message.chat.id=$id | .message.message_id=$m' \
   "$FX/zalo/webhook_sticker.json" > "$TMP/wh_sticker.json"
eq "webhook sticker → ok" "$(zalo "$TMP/wh_sticker.json" | jq -r .ok)" "true"
eq "user gửi sticker vẫn vào dropdown" \
   "$(curl -sS "$B/api/zalo-users/unlinked" | jq -r --arg id "$ZID2" 'any(.[]; .zaloId == $id)')" "true"

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

# Đã link mà gửi sticker → không gọi AI, không sinh event rác.
BEFORE="$(api GET /api/events | jq -r 'length')"
jq --arg id "$ZID" --arg m "s${ZID}9" \
   '.message.from.id=$id | .message.chat.id=$id | .message.message_id=$m' \
   "$FX/zalo/webhook_sticker.json" > "$TMP/wh_sticker2.json"
eq "sticker của user đã link → ok" "$(zalo "$TMP/wh_sticker2.json" | jq -r .ok)" "true"
eq "sticker không tạo event rác" "$(api GET /api/events | jq -r 'length')" "$BEFORE"

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

# Dọn sau khi chạy: link nốt user chỉ-gửi-sticker ở UC8. Không làm thì mỗi lần chạy smoke
# trên prod lại để lại một entry lạ trong dropdown Register của màn demo.
jpost /api/register "{\"username\":\"${U}_sticker\",\"password\":\"123456\",\"zaloId\":\"$ZID2\"}" > /dev/null
eq "user sticker đã rời dropdown" \
   "$(curl -sS "$B/api/zalo-users/unlinked" | jq -r --arg id "$ZID2" 'any(.[]; .zaloId == $id)')" "false"


# ============================================================ Phase 2 (UC10–14)
T="$T1"                  # quay lại business của UC2–7

# ------------------------------------------- UC10 ngày chứng từ + sổ đã đóng
uc "UC10 · ngày trên chứng từ → sổ ngày $DOC tự đồng bộ (②)"
jpost /api/close-day "{\"date\":\"$DOC\"}" > "$TMP/rec10.json"      # như sổ seed sẵn trên prod
eq "sổ $DOC đóng sạch" "$(jq -r .warningCount "$TMP/rec10.json")" "0"
REV10="$(jq -r .summary.revenue "$TMP/rec10.json")"

api POST /api/captures -F type=IMAGE_TRANSFER -F "file=@$ASSETS/transfer_deposit.jpg" > "$TMP/cap10.json"
M10="$(jq -r .resultId "$TMP/cap10.json")"
eq "capture.occurredAt = ngày in trên ảnh" "$(jq -r '.occurredAt[:10]' "$TMP/cap10.json")" "$DOC"
eq "dashboard($DOC).bankIn +380k" "$(dashd bankIn "$DOC")" "1210000"
eq "bankIn hôm nay không đổi"     "$(dash bankIn)" "0"

api GET "/api/daily-records/$DOC" > "$TMP/rec10.json"
eq "sổ đã đóng có warning mới" "$(jq -r --arg m "$M10" \
   'any(.warnings[]; .warningId == "UNMATCHED_MONEY:\($m)" and .status == "OPEN")' "$TMP/rec10.json")" "true"

jpost "/api/money-movements/$M10/classify" "$(cat "$FX/classify_request.json")" > /dev/null
api GET "/api/daily-records/$DOC" > "$TMP/rec10.json"
eq "classify → warning RESOLVED" "$(jq -r --arg m "$M10" \
   '.warnings[] | select(.warningId == "UNMATCHED_MONEY:\($m)") | .status' "$TMP/rec10.json")" "RESOLVED"
eq "summary.revenue không đổi (hero)" "$(jq -r .summary.revenue "$TMP/rec10.json")" "$REV10"

# ------------------------------------------------------------ UC11 bot trả lời
uc "UC11 · bot trả lời trong Zalo (⑤)"
jq --arg m "m${ZID}5" '.message.message_id=$m | .message.text="Bán 2 hộp collagen 300 nghìn tiền mặt"' \
   "$TMP/wh_text.json" > "$TMP/wh_text5.json"
eq "webhook (đã link) vẫn 200 khi có reply" "$(zalo "$TMP/wh_text5.json" | jq -r .ok)" "true"
ZID_NEW="$(LC_ALL=C tr -dc 'a-f0-9' < /dev/urandom | head -c 20)"
jq --arg id "$ZID_NEW" --arg m "m${ZID_NEW}1" \
   '.message.from.id=$id | .message.chat.id=$id | .message.message_id=$m' \
   "$FX/zalo/webhook_text.json" > "$TMP/wh_new.json"
eq "webhook (chưa link) vẫn 200 khi hướng dẫn liên kết" "$(zalo "$TMP/wh_new.json" | jq -r .ok)" "true"
printf '  ℹ️  nội dung reply chỉ kiểm được ở log server / Zalo thật (token rỗng → "bỏ qua reply")\n'

# --------------------------------------------------------------- UC12 báo cáo
uc "UC12 · báo cáo theo khoảng (④)"
FROM="$(TZ=Asia/Ho_Chi_Minh date -v-6d +%F 2>/dev/null || date -d '6 days ago' +%F)"
api GET "/api/reports?from=$FROM&to=$D" > "$TMP/rep.json"
eq "report.from"  "$(jq -r .from "$TMP/rep.json")" "$FROM"
eq "report.days"  "$(jq -r .days "$TMP/rep.json")" "7"
eq "summary.revenue = Σ byDay.revenue" \
   "$(jq -r '.summary.revenue == ([.byDay[].revenue] | add)' "$TMP/rep.json")" "true"
eq "byDay có dòng hôm nay" "$(jq -r --arg d "$D" 'any(.byDay[]; .date == $d)' "$TMP/rep.json")" "true"
eq "byDay hôm nay = dashboard hôm nay" \
   "$(jq -r --arg d "$D" '.byDay[] | select(.date == $d) | .revenue' "$TMP/rep.json")" "$(dash revenue)"
eq "byDay mới nhất trước" "$(jq -r '[.byDay[].date] == ([.byDay[].date] | sort | reverse)' "$TMP/rep.json")" "true"
eq "byType chỉ loại CONFIRMED có bản ghi" \
   "$(jq -r 'all(.byType[]; .count > 0)' "$TMP/rep.json")" "true"
eq "to < from → 400"     "$(code GET "/api/reports?from=$D&to=$FROM")" "400"
eq "thiếu from/to → 400" "$(code GET "/api/reports?to=$D")" "400"
eq "quá 92 ngày → 400"   "$(code GET "/api/reports?from=2026-01-01&to=$D")" "400"

# -------------------------------------------------- UC13 tồn đọng + replay Zalo
uc "UC13 · tồn đọng mọi ngày (③a)"
jpost /api/captures '{"type":"TEXT","text":"Bán 1 hộp yến 250 nghìn chuyển khoản"}' > "$TMP/cap13.json"
EV13="$(jq -r .resultId "$TMP/cap13.json")"
api PUT "/api/events/$EV13" -H 'Content-Type: application/json' \
    -d "{\"occurredAt\":\"${DOC}T15:00:00+07:00\"}" > /dev/null
eq "đổi ngày → sổ $DOC có warning mới (②)" "$(api GET "/api/daily-records/$DOC" | jq -r --arg e "$EV13" \
   'any(.warnings[]; .warningId == "DRAFT_EVENT:\($e)" and .status == "OPEN")' )" "true"
eq "dashboard hôm nay: pastDraftCount" "$(dash pastDraftCount)" "1"

api GET /api/pending > "$TMP/pending.json"
eq "pending có draft ngày cũ" \
   "$(jq -r --arg e "$EV13" 'any(.draftEvents[]; .eventId == $e)' "$TMP/pending.json")" "true"
eq "pending sort cũ nhất trước" \
   "$(jq -r '[.draftEvents[].occurredAt] == ([.draftEvents[].occurredAt] | sort)' "$TMP/pending.json")" "true"
eq "pending.byDate có $DOC" \
   "$(jq -r --arg d "$DOC" 'any(.byDate[]; .date == $d and .draftCount >= 1)' "$TMP/pending.json")" "true"
api POST "/api/events/$EV13/confirm" > /dev/null
eq "confirm → pending giảm" "$(api GET /api/pending | jq -r --arg e "$EV13" \
   'any(.draftEvents[]; .eventId == $e)')" "false"
eq "dashboard hôm nay: pastDraftCount về 0" "$(dash pastDraftCount)" "0"

uc "UC13b · replay tin nhắn Zalo gửi trước khi liên kết (③b)"
ZID3="$(LC_ALL=C tr -dc 'a-f0-9' < /dev/urandom | head -c 20)"
for i in 1 2; do
  jq --arg id "$ZID3" --arg m "r${ZID3}$i" \
     '.message.from.id=$id | .message.chat.id=$id | .message.message_id=$m' \
     "$FX/zalo/webhook_text.json" > "$TMP/wh_r$i.json"
  zalo "$TMP/wh_r$i.json" > /dev/null
done
jq --arg id "$ZID3" --arg m "r${ZID3}s" \
   '.message.from.id=$id | .message.chat.id=$id | .message.message_id=$m' \
   "$FX/zalo/webhook_sticker.json" > "$TMP/wh_rs.json"
zalo "$TMP/wh_rs.json" > /dev/null

U3="${U}_replay"
jpost /api/register "{\"username\":\"$U3\",\"password\":\"123456\",\"zaloId\":\"$ZID3\"}" > "$TMP/s3.json"
T="$(jq -r .token "$TMP/s3.json")"
api POST "/api/zalo-users/$ZID3/replay" > "$TMP/replay.json"
eq "replay.zaloId"  "$(jq -r .zaloId "$TMP/replay.json")" "$ZID3"
eq "replay.replayed" "$(jq -r .replayed "$TMP/replay.json")" "2"
eq "replay.done"     "$(jq -r .done "$TMP/replay.json")" "2"
eq "replay.skipped (sticker)" "$(jq -r .skipped "$TMP/replay.json")" "1"
eq "2 draft từ message cũ" "$(api GET "/api/events?status=DRAFT" | jq -r 'length')" "2"
eq "draft.source" "$(api GET "/api/events?status=DRAFT" | jq -r '.[0].source')" "ZALO"
api POST "/api/zalo-users/$ZID3/replay" > "$TMP/replay2.json"
eq "replay lần 2 không xử lý lại" "$(jq -r .replayed "$TMP/replay2.json")" "0"
eq "zaloId không phải của mình → 404" "$(code POST "/api/zalo-users/$ZID/replay")" "404"

# --------------------------------------------------- UC14 đối soát lịch sử CK
uc "UC14 · ảnh lịch sử chuyển khoản → batch + dedupe (①)"
T="$T1"
api POST /api/captures -F type=IMAGE_BANK_HISTORY -F "file=@$ASSETS/bank_history.jpg" > "$TMP/cap14.json"
eq "capture.status"     "$(jq -r .status "$TMP/cap14.json")" "DONE"
eq "capture.resultType" "$(jq -r .resultType "$TMP/cap14.json")" "MONEY_MOVEMENT_BATCH"
eq "capture.resultId null" "$(jq -r .resultId "$TMP/cap14.json")" "null"
eq "resultIds (eval)"      "$(jq -r '.resultIds | length' "$TMP/cap14.json")" "3"
eq "skippedCount (eval)"   "$(jq -r .skippedCount "$TMP/cap14.json")" "2"
M14="$(jq -r '.resultIds[0]' "$TMP/cap14.json")"
api GET "/api/money-movements/$M14" > "$TMP/m14.json"
eq "movement.captureType" "$(jq -r .captureType "$TMP/m14.json")" "IMAGE_BANK_HISTORY"
eq "movement.status"      "$(jq -r .status "$TMP/m14.json")" "UNMATCHED"
eq "có dòng OUT (eval)" "$(api GET /api/money-movements \
   | jq -r 'any(.[]; .captureType == "IMAGE_BANK_HISTORY" and .direction == "OUT")')" "true"
eq "dòng ngày 10/09 (eval)" "$(api GET /api/money-movements \
   | jq -r 'any(.[]; .captureType == "IMAGE_BANK_HISTORY" and (.occurredAt | startswith("2026-09-10")))')" "true"

api POST /api/captures -F type=IMAGE_RECEIPT -F "file=@$ASSETS/receipt.jpg" > /dev/null &   # warm
wait
api POST /api/captures -F type=IMAGE_BANK_HISTORY -F "file=@$ASSETS/bank_history.jpg" > "$TMP/cap14b.json"
eq "gửi lại → không tạo thêm" "$(jq -r '.resultIds | length' "$TMP/cap14b.json")" "0"
eq "gửi lại → skipped 5"      "$(jq -r .skippedCount "$TMP/cap14b.json")" "5"
eq "gửi lại vẫn DONE"         "$(jq -r .status "$TMP/cap14b.json")" "DONE"

# Ảnh một giao dịch gửi nhầm type → không được suy diễn thành 1 dòng (rule prompt §15).
api POST /api/captures -F type=IMAGE_BANK_HISTORY -F "file=@$ASSETS/receipt.jpg" > "$TMP/cap14c.json"
eq "ảnh không phải danh sách → FAILED" "$(jq -r .status "$TMP/cap14c.json")" "FAILED"
eq "error UNRECOGNIZED_IMAGE" "$(jq -r .error "$TMP/cap14c.json")" "UNRECOGNIZED_IMAGE"

# ------------------------------------------------ tiền ra (ảnh CK của chính chủ hộ)
uc "Tiền ra · ảnh MoMo chủ hộ tự chụp (eval M8)"
EVID="$P/test-data/evidence"
api POST /api/captures -F type=IMAGE_TRANSFER \
    -F "file=@$EVID/synthetic_transfer_M8_owner_out.jpg" > "$TMP/capout.json"
MOUT="$(jq -r .resultId "$TMP/capout.json")"
api GET "/api/money-movements/$MOUT" > "$TMP/mout.json"
eq "direction OUT (eval)"   "$(jq -r .direction "$TMP/mout.json")" "OUT"
eq "amount (eval)"          "$(jq -r .amount "$TMP/mout.json")" "100000"
eq "counterparty = người nhận, không phải chủ hộ (eval)" \
   "$(jq -r '.counterparty | ascii_upcase | contains("HANH")' "$TMP/mout.json")" "true"
eq "occurredAt = ngày trên ảnh" "$(jq -r '.occurredAt[:10]' "$TMP/mout.json")" "2026-08-14"
eq "tiền ra không có candidate" "$(jq -r '.candidates | length' "$TMP/mout.json")" "0"
eq "bankIn không tính tiền ra" "$(dashd bankIn 2026-08-14)" "0"
eq "match tiền ra → 409" "$(code POST "/api/money-movements/$MOUT/match" \
    -H 'Content-Type: application/json' -d "{\"eventId\":\"$EV1\"}")" "409"
jpost "/api/money-movements/$MOUT/classify" '{"type":"OTHER"}' > "$TMP/mout.json"
eq "classify tiền ra → CLASSIFIED" "$(jq -r .status "$TMP/mout.json")" "CLASSIFIED"

# ------------------------------------------------------------------- contract
uc "Contract"
eq "/api/docs public → 200"        "$(code GET /api/docs)" "200"
eq "/api/openapi.yaml public → 200" "$(code GET /api/openapi.yaml)" "200"
eq "spec có đủ path"  "$(curl -sS "$B/api/openapi.yaml" | grep -c '^  /api/')" "24"

SAVED="$T"; T="tb_sai"
eq "token sai → 401" "$(code GET /api/events)" "401"
T="$SAVED"
eq "logout → 204" "$(code POST /api/logout)" "204"
eq "token đã logout → 401" "$(code GET /api/events)" "401"

printf '\n\033[1m%s pass · %s fail\033[0m\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
