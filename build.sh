#!/bin/zsh
# Build ColumnTamer osax. arm64 + arm64e. Ad-hoc signed (SIP off path).
set -eu

cd "$(dirname "$0")"
ROOT=$(pwd)
BUILD="$ROOT/build"
BUNDLE="$BUILD/ColumnTamer.osax"

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
    -o "$BUILD/ColumnTamer.$arch.dylib" \
    "$ROOT/src/main.m"
}

build_arch arm64
build_arch arm64e

echo "=== lipo ==="
lipo -create \
  "$BUILD/ColumnTamer.arm64.dylib" \
  "$BUILD/ColumnTamer.arm64e.dylib" \
  -output "$BUILD/ColumnTamer"

echo "=== bundle ==="
mkdir -p "$BUNDLE/Contents/MacOS" \
         "$BUNDLE/Contents/Resources"
cp "$BUILD/ColumnTamer"     "$BUNDLE/Contents/MacOS/ColumnTamer"
cp "$ROOT/Info.plist"       "$BUNDLE/Contents/Info.plist"
cp "$ROOT/ColumnTamer.sdef" "$BUNDLE/Contents/Resources/ColumnTamer.sdef"

printf 'osax????' > "$BUNDLE/Contents/PkgInfo"

echo "=== ad-hoc sign ==="
codesign --force --sign - "$BUNDLE/Contents/MacOS/ColumnTamer"
codesign --force --sign - "$BUNDLE"

echo "=== verify ==="
file "$BUNDLE/Contents/MacOS/ColumnTamer"
lipo -archs "$BUNDLE/Contents/MacOS/ColumnTamer"
codesign -dv "$BUNDLE" 2>&1 | grep -E "Identifier|Signature"

echo "=== DONE ==="
echo "osax: $BUNDLE"
