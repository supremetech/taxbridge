#!/usr/bin/env bash
# Copy contract fixtures → assets/fixtures (không sửa tay bản copy).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/../taxbridge-prompt/contract/fixtures"
DST="$ROOT/assets/fixtures"
rm -rf "$DST" && mkdir -p "$DST"
cp "$SRC"/*.json "$DST"/
echo "synced $(ls "$DST" | wc -l | tr -d ' ') fixtures → assets/fixtures"
