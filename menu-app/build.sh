#!/bin/zsh
# Build ColumnTamerMenu menubar app. arm64 + arm64e. Ad-hoc signed.
set -eu
cd "$(dirname "$0")"
ROOT=$(pwd)/..
BUILD="$ROOT/build/menubuild"
APP="$BUILD/ColumnTamerMenu.app"

echo "=== clean ==="
rm -rf "$BUILD"
mkdir -p "$BUILD"

build_arch() {
  local arch="$1"
  echo "=== compile $arch ==="
  swiftc \
    -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
    -target ${arch}-apple-macosx10.15 \
    -parse-as-library \
    -o "$BUILD/ColumnTamerMenu.$arch" \
    "$ROOT/menu-app/Main.swift"
}

build_arch arm64
build_arch arm64e

echo "=== lipo ==="
lipo -create \
  "$BUILD/ColumnTamerMenu.arm64" \
  "$BUILD/ColumnTamerMenu.arm64e" \
  -output "$BUILD/ColumnTamerMenu"

echo "=== bundle ==="
mkdir -p "$APP/Contents/MacOS"
cp "$BUILD/ColumnTamerMenu"   "$APP/Contents/MacOS/ColumnTamerMenu"
cp "$ROOT/menu-app/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "=== sign ==="
codesign --force --sign - "$APP/Contents/MacOS/ColumnTamerMenu"
codesign --force --sign - "$APP"

echo "=== verify ==="
file "$APP/Contents/MacOS/ColumnTamerMenu"
lipo -archs "$APP/Contents/MacOS/ColumnTamerMenu"
codesign -dv "$APP" 2>&1 | grep -E "Identifier|Signature"
echo "=== DONE ==="
echo "app: $APP"
