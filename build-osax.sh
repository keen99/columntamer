#!/bin/zsh
# build-osax.sh — compile ColumnTamer osax leaf (x86_64 + arm64 + arm64e).
# UNSIGNED. Signing done by scripts/build.sh orchestrator (timed).
# Called by scripts/build.sh, scripts/release.sh, scripts/package.sh.
set -eu

cd "$(dirname "$0")"
ROOT=$(pwd)
BUILD="$ROOT/build"
BUNDLE="$BUILD/ColumnTamer.osax"

echo "=== clean osax build ==="
rm -rf "$BUILD"
mkdir -p "$BUILD"

build_arch() {
  local arch="$1"
  echo "=== compile $arch ==="
  clang -arch "$arch" -dynamiclib -fobjc-arc \
    -isysroot "$(xcrun --sdk macosx --show-sdk-path)" \
    -mmacosx-version-min=10.15 \
    -framework Cocoa -framework Foundation \
    -o "$BUILD/ColumnTamer.$arch.dylib" \
    "$ROOT/src/main.m"
}

build_arch x86_64
build_arch arm64
build_arch arm64e

echo "=== lipo ==="
lipo -create \
  "$BUILD/ColumnTamer.x86_64.dylib" \
  "$BUILD/ColumnTamer.arm64.dylib" \
  "$BUILD/ColumnTamer.arm64e.dylib" \
  -output "$BUILD/ColumnTamer"

echo "=== bundle (unsigned) ==="
mkdir -p "$BUNDLE/Contents/MacOS" \
         "$BUNDLE/Contents/Resources"
cp "$BUILD/ColumnTamer"     "$BUNDLE/Contents/MacOS/ColumnTamer"
cp "$ROOT/Info.plist"       "$BUNDLE/Contents/Info.plist"
cp "$ROOT/ColumnTamer.sdef" "$BUNDLE/Contents/Resources/ColumnTamer.sdef"

printf 'osax????' > "$BUNDLE/Contents/PkgInfo"

echo "=== DONE (unsigned) ==="
echo "osax: $BUNDLE"
