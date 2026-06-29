#!/bin/zsh
# menu-app/build.sh — compile ColumnTamerMenu menubar app leaf (arm64 + arm64e).
# UNSIGNED. Signing done by scripts/build.sh orchestrator (timed).
set -eu
cd "$(dirname "$0")"
ROOT=$(pwd)/..
BUILD="$ROOT/build/menubuild"
APP="$BUILD/ColumnTamerMenu.app"

echo "=== clean menu build ==="
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

echo "=== bundle (unsigned) ==="
mkdir -p "$APP/Contents/MacOS"
cp "$BUILD/ColumnTamerMenu"   "$APP/Contents/MacOS/ColumnTamerMenu"
cp "$ROOT/menu-app/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "=== DONE (unsigned) ==="
echo "app: $APP"
