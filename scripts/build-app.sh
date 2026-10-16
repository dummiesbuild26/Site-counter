#!/usr/bin/env bash
# Builds "Site Counter.app" into ./build (universal: Apple Silicon + Intel).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --arch arm64 --arch x86_64
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

APP="build/Site Counter.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/SiteCounter" "$APP/Contents/MacOS/SiteCounter"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Ad-hoc sign so macOS will launch it locally.
codesign --force --deep --sign - "$APP"

echo "Built: $APP"
echo "Drag it into /Applications, or run: open \"$APP\""
