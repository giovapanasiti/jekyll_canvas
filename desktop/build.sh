#!/usr/bin/env bash
# Builds dist/Jekyll Canvas.app (no Xcode project, swiftc only).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
APP="$ROOT/dist/Jekyll Canvas.app"
CONTENTS="$APP/Contents"

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

echo "==> swiftc"
swiftc -O -swift-version 5 -target arm64-apple-macos13.0 \
  -framework AppKit -framework WebKit \
  "$HERE"/Sources/*.swift \
  -o "$CONTENTS/MacOS/JekyllCanvas"

echo "==> Info.plist"
cp "$HERE/Info.plist" "$CONTENTS/Info.plist"

echo "==> engine"
mkdir -p "$CONTENTS/Resources/engine"
if [ -d "$ROOT/engine" ]; then
  rsync -a --delete \
    --exclude '/test/' --exclude '/Gemfile.lock' --exclude '/.bundle/' --exclude '/script/' \
    --exclude '.DS_Store' \
    "$ROOT/engine/" "$CONTENTS/Resources/engine/"
else
  echo "warning: $ROOT/engine does not exist yet; bundled an empty engine dir" >&2
fi

echo "==> icon"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
swiftc -O "$HERE/icon/make_icon.swift" -o "$TMP/make_icon"
"$TMP/make_icon" "$TMP/icon_1024.png"
ICONSET="$TMP/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$TMP/icon_1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z $d $d "$TMP/icon_1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$CONTENTS/Resources/AppIcon.icns"

echo "==> codesign (ad hoc)"
codesign --force --deep -s - "$APP"

echo "Built: $APP"
