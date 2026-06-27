#!/bin/zsh
# Build ColumnTamer osax. arm64 + arm64e.
# Signing identity via SIGN_IDENTITY env (default ad-hoc). Apple Dev preferred
# for TCC stability — see AGENTS.md §Conventions.
set -eu

SIGN="${SIGN_IDENTITY:--}"
if [[ "${SIGN_HARDEN:-}" == "1" ]]; then
  HARDSIGN=(-o runtime --timestamp)
else
  HARDSIGN=()
fi

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
    -mmacosx-version-min=10.15 \
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

echo "=== sign: $SIGN ==="
codesign --force --sign "$SIGN" "${HARDSIGN[@]}" "$BUNDLE/Contents/MacOS/ColumnTamer"
codesign --force --sign "$SIGN" "${HARDSIGN[@]}" "$BUNDLE"

echo "=== verify ==="
file "$BUNDLE/Contents/MacOS/ColumnTamer"
lipo -archs "$BUNDLE/Contents/MacOS/ColumnTamer"
codesign -dv "$BUNDLE" 2>&1 | grep -E "Identifier|Signature"

echo "=== DONE ==="
echo "osax: $BUNDLE"
