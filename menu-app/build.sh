#!/bin/bash
# menu-app/build.sh — compile ColumnTamer menubar app leaf (x86_64 + arm64 + arm64e).
set -eu
cd "$(dirname "$0")"
BUILD="$(pwd)/../build/menubuild"
APP="$BUILD/ColumnTamer.app"
mkdir -p "$BUILD"

# xcodebuild requires a minimal xcodeproj or SDK; use swiftc direct + xcrun SDK.
SDK="$(xcrun --show-sdk-path 2>/dev/null)"
MACOS_MIN="10.15"

# source files (glob .swift)
SWIFT_ARGS=(
  -target "x86_64-apple-macosx$MACOS_MIN"
  -sdk "$SDK"
  -parse-as-library
  -framework Cocoa
  -framework CoreFoundation
  Main.swift
)

# Build per-arch (arm64e requires arm64e triple, no x86_64 cross).
ARCHS=(x86_64 arm64 arm64e)
for arch in "${ARCHS[@]}"; do
  echo "▸ build $arch"
  swiftc \
    -target "${arch}-apple-macosx$MACOS_MIN" \
    -sdk "$SDK" \
    -parse-as-library \
    -framework Cocoa \
    -framework CoreFoundation \
    -o "$BUILD/ColumnTamer.$arch" \
    Main.swift
done

# lipo universal
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
echo "▸ lipo universal"
lipo -create \
  "$BUILD/ColumnTamer.x86_64" \
  "$BUILD/ColumnTamer.arm64" \
  "$BUILD/ColumnTamer.arm64e" \
  -output "$BUILD/ColumnTamer"

# PkgInfo + Info.plist
cp Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Move binary
cp "$BUILD/ColumnTamer"   "$APP/Contents/MacOS/ColumnTamer"
# Icon
if [[ -f appicon.icns ]]; then
  cp appicon.icns "$APP/Contents/Resources/appicon.icns"
fi

# Arch guard
_got=$(lipo -archs "$APP/Contents/MacOS/ColumnTamer")
echo "▸ archs: $_got"
if [[ "$_got" != *"x86_64"* ]] || [[ "$_got" != *"arm64"* ]] || [[ "$_got" != *"arm64e"* ]]; then
  echo "⚠ arch slice missing in lipo output (got: $_got)"
  exit 1
fi

echo "✓ Built $APP"
