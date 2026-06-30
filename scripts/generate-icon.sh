#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${ROOT}/Resources/AppIcon.png"
ICONSET="${ROOT}/Resources/AppIcon.iconset"
OUT="${ROOT}/Resources/AppIcon.icns"

if [ ! -f "$SRC" ]; then
  echo "错误: 找不到 ${SRC}" >&2
  exit 1
fi

rm -rf "$ICONSET"
mkdir -p "$ICONSET"

declare -a SIZES=(
  "16:icon_16x16.png"
  "32:icon_16x16@2x.png"
  "32:icon_32x32.png"
  "64:icon_32x32@2x.png"
  "128:icon_128x128.png"
  "256:icon_128x128@2x.png"
  "256:icon_256x256.png"
  "512:icon_256x256@2x.png"
  "512:icon_512x512.png"
  "1024:icon_512x512@2x.png"
)

for entry in "${SIZES[@]}"; do
  size="${entry%%:*}"
  name="${entry##*:}"
  sips -z "$size" "$size" "$SRC" --out "$ICONSET/$name" >/dev/null
done

iconutil -c icns "$ICONSET" -o "$OUT"
rm -rf "$ICONSET"

echo "✅ 已生成 ${OUT}"
