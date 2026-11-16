#!/usr/bin/env bash
# Builds Grammable.app (universal: Apple silicon + Intel) and a distributable zip.
#
#   ./scripts/build-app.sh                 # ad-hoc signed build in ./dist
#   VERSION=1.2.0 ./scripts/build-app.sh   # set the version
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
#   NOTARY_PROFILE=grammable ./scripts/build-app.sh   # signed + notarized release
#
# Grammable — Copyright (C) 2026 Udaya Lakmal — GPL-3.0-or-later
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
VERSION="${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)}"
VERSION="${VERSION:-0.1.0}"
BUILD="${BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"   # "-" = ad-hoc
ARCHS="${ARCHS:-arm64 x86_64}"
DIST="$ROOT/dist"
APP="$DIST/Grammable.app"

echo "▸ Building Grammable $VERSION ($BUILD) for: $ARCHS"
ARCH_FLAGS=()
for a in $ARCHS; do ARCH_FLAGS+=(--arch "$a"); done
swift build -c release "${ARCH_FLAGS[@]}"
BIN_DIR="$(swift build -c release "${ARCH_FLAGS[@]}" --show-bin-path)"

echo "▸ Assembling app bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Grammable" "$APP/Contents/MacOS/Grammable"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"

echo "▸ Generating icon"
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
SRC="Resources/AppIcon-1024.png"
[ -f "$SRC" ] || swift scripts/make-icon.swift "$SRC"
for size in 16 32 128 256 512; do
  sips -z $size $size "$SRC" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z $double $double "$SRC" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

echo "▸ Signing ($SIGN_IDENTITY)"
if [ "$SIGN_IDENTITY" = "-" ]; then
  codesign --force --sign - "$APP"
else
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
fi
codesign --verify --strict "$APP"

ZIP="$DIST/Grammable-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

if [ -n "${NOTARY_PROFILE:-}" ]; then
  echo "▸ Notarizing (profile: $NOTARY_PROFILE)"
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
fi

shasum -a 256 "$ZIP" | tee "$ZIP.sha256"
echo "✓ Done: $APP"
echo "✓ Zip:  $ZIP"
