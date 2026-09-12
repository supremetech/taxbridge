#!/usr/bin/env bash
# Sinh nền tiếng ồn cửa hàng mặt phố (xe cộ + lao xao) cho case A2.
# Output: 44.1kHz mono, 40 giây, đủ phủ mọi clip ghi âm ngắn.
set -e
OUT="${1:-$(dirname "$0")/evidence/synthetic_ambience_shopfront.m4a}"

ffmpeg -y -hide_banner -loglevel error \
  -f lavfi -t 40 -i "anoisesrc=color=brown:sample_rate=44100:amplitude=0.9" \
  -f lavfi -t 40 -i "anoisesrc=color=pink:sample_rate=44100:amplitude=0.5" \
  -f lavfi -t 40 -i "anoisesrc=color=brown:sample_rate=44100:amplitude=1.0" \
  -filter_complex "\
    [0:a]lowpass=f=320,volume=1.0[rumble];\
    [1:a]bandpass=f=1400:width_type=h:w=1600,tremolo=f=0.7:d=0.5,volume=0.35[chatter];\
    [2:a]lowpass=f=900,highpass=f=120,tremolo=f=0.11:d=0.92,volume=0.55[bikes];\
    [rumble][chatter][bikes]amix=inputs=3:duration=first:normalize=0,\
    highpass=f=45,alimiter=limit=0.85,volume=1.0[out]" \
  -map "[out]" -ac 1 -ar 44100 "$OUT"

echo "ambience -> $OUT"
