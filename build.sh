#!/bin/zsh
# Build XPLock osax. arm64 + arm64e. No signing (SIP off, libvalidation off).
set -eu

cd "$(dirname "$0")"
ROOT=$(pwd)
BUILD="$ROOT/build"
BUNDLE="$BUILD/XPLock.osax"

echo "=== clean ==="
rm -rf "$BUILD"
mkdir -p "$BUILD"

build_arch() {
  local arch="$1"
  echo "=== compile $arch ==="
  clang -arch "$arch" -dynamiclib -fobjc-arc \
    -isysroot "$(xcrun --sdk macosx --show-sdk-path)" \
    -mmacosx-version-min=11.0 \
    -framework Cocoa -framework Foundation \
    -o "$BUILD/XPLock.$arch.dylib" \
    "$ROOT/src/main.m"
}

build_arch arm64
build_arch arm64e

echo "=== lipo ==="
lipo -create \
  "$BUILD/XPLock.arm64.dylib" \
  "$BUILD/XPLock.arm64e.dylib" \
  -output "$BUILD/XPLock"

echo "=== bundle ==="
mkdir -p "$BUNDLE/Contents/MacOS" \
         "$BUNDLE/Contents/Resources"
cp "$BUILD/XPLock"        "$BUNDLE/Contents/MacOS/XPLock"
cp "$ROOT/Info.plist"     "$BUNDLE/Contents/Info.plist"
cp "$ROOT/XPLock.sdef"    "$BUNDLE/Contents/Resources/XPLock.sdef"

# minimal PkgInfo
printf 'osax????' > "$BUNDLE/Contents/PkgInfo"

echo "=== verify ==="
file "$BUNDLE/Contents/MacOS/XPLock"
lipo -archs "$BUNDLE/Contents/MacOS/XPLock"

echo "=== DONE ==="
echo "osax: $BUNDLE"
