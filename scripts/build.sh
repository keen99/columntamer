#!/bin/bash
#
# build.sh — ColumnTamer build + sign orchestrator. Called by run.sh, release.sh.
#   Usage: build.sh [Debug|Release]   (default Debug)
#
#   Drives leaf builders (build-osax.sh, menu-app/build.sh) which produce
#   UNSIGNED artifacts. Signs here so timing isolated from compile.
#
#   Signing auto-picked:
#     Release + DEVELOPER_IDENTITY  → DevID (hardened runtime + timestamp)
#     else Apple Development cert if present → sign (TCC stable, no timestamp)
#     else ad-hoc "-"
#
set -eu
cd "$(dirname "$0")/.."
ROOT=$(pwd)

CONFIG="${1:-Debug}"

[[ -f VERSION ]] || { echo "✗ VERSION missing"; exit 1; }
VERSION="$(tr -d '[:space:]' < VERSION)"
BUILD_NUM="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
GIT_COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo dev)"
GIT_BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo dev)"
BUILD_DATE="$(date -u '+%Y-%m-%d %H:%M UTC')"
echo "▸ Version $VERSION (build $BUILD_NUM, commit $GIT_COMMIT)"

# ── Pick identity ──────────────────────────────────────────────────────────
if [[ "$CONFIG" == "Release" && -n "${DEVELOPER_IDENTITY:-}" ]]; then
  SIGN="$DEVELOPER_IDENTITY"; HARDSIGN=(-o runtime --timestamp); HARD=1
elif security find-identity -v -p codesigning 2>/dev/null | grep -q "Apple Development"; then
  SIGN="$(security find-identity -v -p codesigning | grep "Apple Development" | head -1 | sed 's/.*"\(.*\)".*/\1/')"
  HARDSIGN=(); HARD=0
else
  SIGN="-"; HARDSIGN=(); HARD=0
fi

# ── Compile both leaves (unsigned) ─────────────────────────────────────────
T0=$(date +%s)
echo "▸ Building $CONFIG (osax + menu)"
"$ROOT/build-osax.sh" >/dev/null
"$ROOT/menu-app/build.sh" >/dev/null
T1=$(date +%s); BC=$((T1 - T0))

OSAX="$ROOT/build/ColumnTamer.osax"
MENU="$ROOT/build/menubuild/ColumnTamerMenu.app"

# ── Stamp Info.plist copies (source immutable) ─────────────────────────────
if [[ "$CONFIG" == "Debug" ]]; then
  DISP_VER="${VERSION}+${GIT_COMMIT}"
else
  DISP_VER="$VERSION"
fi
for PLIST in "$OSAX/Contents/Info.plist" "$MENU/Contents/Info.plist"; do
  [[ -f "$PLIST" ]] || continue
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $DISP_VER" \
    -c "Set :CFBundleVersion $BUILD_NUM" \
    -c "Set :GitCommit $GIT_COMMIT" \
    -c "Set :GitBranch $GIT_BRANCH" \
    -c "Set :BuildDate $BUILD_DATE" "$PLIST"
done

# ── Sign (separate step, timed) ────────────────────────────────────────────
T2=$(date +%s)
codesign --force --sign "$SIGN" "${HARDSIGN[@]}" "$OSAX/Contents/MacOS/ColumnTamer"
codesign --force --sign "$SIGN" "${HARDSIGN[@]}" "$OSAX"
codesign --force --sign "$SIGN" "${HARDSIGN[@]}" "$MENU/Contents/MacOS/ColumnTamerMenu"
codesign --force --sign "$SIGN" "${HARDSIGN[@]}" "$MENU"
T3=$(date +%s); SC=$((T3 - T2))

echo "▸ Built in ${BC}s, signed in ${SC}s → $SIGN"
echo "▸ osax: $OSAX"
echo "▸ menu: $MENU"
