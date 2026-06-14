#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOGO="$ROOT/logo.png"
ICONSET="$ROOT/build/AppIcon.iconset"
ICNS="$ROOT/Resources/AppIcon.icns"

if [[ ! -f "$LOGO" ]]; then
    echo "Logo not found at $LOGO" >&2
    exit 1
fi

mkdir -p "$ICONSET"
rm -f "$ICONSET"/*.png

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
    filename="${entry##*:}"
    sips -z "$size" "$size" "$LOGO" --out "$ICONSET/$filename" >/dev/null
done

mkdir -p "$(dirname "$ICNS")"
iconutil -c icns "$ICONSET" -o "$ICNS"

echo "Generated $ICNS"
