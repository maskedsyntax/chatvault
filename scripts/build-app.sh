#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG="${1:-release}"
APP="$ROOT/build/ChatVault.app"
BINARY="$ROOT/.build/$CONFIG/ChatVault"
LOGO="$ROOT/logo.png"

echo "Building ChatVault ($CONFIG)..."
swift build -c "$CONFIG"

echo "Generating app icon..."
chmod +x "$ROOT/scripts/generate-app-icon.sh"
"$ROOT/scripts/generate-app-icon.sh"

echo "Packaging $APP ..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$BINARY" "$APP/Contents/MacOS/ChatVault"
chmod +x "$APP/Contents/MacOS/ChatVault"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$LOGO" "$APP/Contents/Resources/logo.png"

echo "Done: $APP"
echo "Launch with: open \"$APP\""
