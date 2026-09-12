#!/usr/bin/env bash
# Trộn giọng đã thu với nền tiếng ồn ở mức SNR cố định -> tạo case A2 có kiểm soát.
#
#   ./mix_noise.sh giong_sach.m4a ket_qua.m4a 12
#
# Tham số 3 là SNR (dB). Gợi ý: 18 = ồn nhẹ, 12 = ồn rõ (khuyến nghị cho A2),
# 6 = rất ồn (dùng để tìm ngưỡng gãy của ASR).
#
# SNR đo theo độ ồn gated EBU R128 (LUFS) chứ không phải RMS toàn file: RMS bị
# kéo xuống bởi khoảng lặng nên sẽ báo SNR thấp hơn thực tế (đo được lệch ~3.5dB
# trên bộ ghi âm này), dẫn tới dán nhãn sai khi dò ngưỡng gãy của ASR.
set -e
VOICE="$1"; OUT="$2"; SNR="${3:-12}"
NOISE="${4:-$(dirname "$0")/evidence/synthetic_ambience_shopfront.m4a}"

[ -f "$VOICE" ] || { echo "Không thấy file giọng: $VOICE"; exit 1; }
[ -f "$NOISE" ] || { echo "Không thấy file nền: $NOISE (chạy gen_noise.sh trước)"; exit 1; }

# Mức gated (LUFS). Nếu file quá ngắn để ebur128 tích phân được thì lùi về RMS.
lvl() {
  local v
  v=$(ffmpeg -hide_banner -nostats -i "$1" -af ebur128 -f null /dev/null 2>&1 \
      | grep -E '^\s+I:\s+-?[0-9.]+ LUFS' | tail -1 \
      | sed -E 's/.*I:[[:space:]]*(-?[0-9.]+) LUFS.*/\1/')
  if [ -z "$v" ] || [ "$v" = "-inf" ]; then
    v=$(ffmpeg -hide_banner -nostats -i "$1" -filter:a volumedetect -f null /dev/null 2>&1 \
        | grep mean_volume | sed -E 's/.*mean_volume: (-?[0-9.]+) dB/\1/')
    echo "  (cảnh báo: dùng RMS thay cho LUFS cho $1)" >&2
  fi
  echo "$v"
}

VL=$(lvl "$VOICE"); NL=$(lvl "$NOISE")
ADJ=$(python3 -c "print(f'{($VL)-($NL)-($SNR):.2f}')")

ffmpeg -y -hide_banner -loglevel error \
  -i "$VOICE" -i "$NOISE" \
  -filter_complex "[1:a]volume=${ADJ}dB,atrim=0:99[n];[0:a][n]amix=inputs=2:duration=shortest:normalize=0,alimiter=limit=0.95[out]" \
  -map "[out]" -c:a aac -b:a 96k -ar 44100 -ac 1 "$OUT"

echo "$OUT  (giọng ${VL} LUFS / nền ${NL} LUFS -> SNR ${SNR}dB, nền chỉnh ${ADJ}dB)"
