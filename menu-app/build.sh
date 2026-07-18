#!/bin/zsh
# menu-app/build.sh — compile ColumnTamerMenu menubar app leaf (x86_64 + arm64 + arm64e).
# UNSIGNED. Signing done by scripts/build.sh orchestrator (timed).
# UNIVERSAL REQUIRED: all 3 archs. Intel Mac = x86_64 only. Dropping any slice
# = silent "not supported on this version of macOS" on matching Mac. See AGENTS.md.
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

build_arch x86_64
build_arch arm64
build_arch arm64e

echo "=== lipo ==="
lipo -create \
  "$BUILD/ColumnTamerMenu.x86_64" \
  "$BUILD/ColumnTamerMenu.arm64" \
  "$BUILD/ColumnTamerMenu.arm64e" \
  -output "$BUILD/ColumnTamerMenu"

echo "=== bundle (unsigned) ==="
mkdir -p "$APP/Contents/MacOS"
cp "$BUILD/ColumnTamerMenu"   "$APP/Contents/MacOS/ColumnTamerMenu"
cp "$ROOT/menu-app/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# ── Arch guard: UNIVERSAL REQUIRED. Fail build (not runtime) if any slice missing. ──
echo "=== arch check ==="
_got=$(lipo -archs "$APP/Contents/MacOS/ColumnTamerMenu")
for _a in x86_64 arm64 arm64e; do
  case " $_got " in
    *" $_a "*) ;;
    *) { echo "✗ MISSING ARCH $_a (got: $_got). Intel/AppleSilicon boot would fail."; exit 1; } ;;
  esac
done
echo "✓ universal: $_got"

echo "=== DONE (unsigned) ==="
echo "app: $APP"
