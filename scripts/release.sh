#!/bin/zsh
#
# release.sh — ColumnTamer Release build (osax + menu app) + smart-sign.
#   Called by `make release`. Produces signed artifacts in build/. For pkg
#   installer run `make package`.
#
#   Signing (AGENTS.md §Conventions):
#     • DEVELOPER_IDENTITY set       → DevID sign (hardened runtime)
#     • Apple Development cert found → sign Apple Dev (TCC stable)
#     • else                         → ad-hoc "-" (fallback)
#
set -eu
cd "$(dirname "$0")/.."
ROOT=$(pwd)

# ── Smart-pick identity ────────────────────────────────────────────────────
if [[ -n "${DEVELOPER_IDENTITY:-}" ]]; then
  SIGN="$DEVELOPER_IDENTITY"
  SIGN_TEAM="${APPLE_TEAM_ID:-}"
  echo "▸ Signing with Developer ID: $SIGN"
elif security find-identity -v -p codesigning 2>/dev/null | grep -q "Apple Development"; then
  SIGN="$(security find-identity -v -p codesigning | grep "Apple Development" | head -1 | sed 's/.*"\(.*\)".*/\1/')"
  SIGN_TEAM="$(security find-certificate -c "Apple Development" -p 2>/dev/null \
    | openssl x509 -noout -subject 2>/dev/null | grep -oE 'OU=[A-Z0-9]+' | cut -d= -f2)"
  echo "▸ Signing with Apple Development cert: $SIGN"
else
  SIGN="-"
  SIGN_TEAM=""
  echo "▸ No signing identity found — ad-hoc"
fi
export SIGN_IDENTITY="$SIGN"
export SIGN_TEAM
export SIGN_HARDEN=1

echo "▸ Building osax"
"$ROOT/build.sh" >/dev/null

echo "▸ Building menu app"
"$ROOT/menu-app/build.sh" >/dev/null

# ── Version stamp (osax + menu Info.plist copies in build/) ────────────────
if [[ -f "$ROOT/VERSION" ]]; then
  VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
  BUILD_NUM="$(cd "$ROOT" && git rev-list --count HEAD 2>/dev/null || echo 1)"
  for PLIST in "$ROOT/build/ColumnTamer.osax/Contents/Info.plist" \
               "$ROOT/build/menubuild/ColumnTamerMenu.app/Contents/Info.plist"; do
    [[ -f "$PLIST" ]] && /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" \
      -c "Set :CFBundleVersion $BUILD_NUM" "$PLIST" 2>/dev/null || true
  done
fi

# ── Verify ─────────────────────────────────────────────────────────────────
echo "▸ Signature check"
codesign -dv "$ROOT/build/ColumnTamer.osax" 2>&1 | grep -E "Identifier|Signature|TeamIdentifier"
codesign -dv "$ROOT/build/menubuild/ColumnTamerMenu.app" 2>&1 | grep -E "Identifier|Signature|TeamIdentifier"

echo
echo "══════════════════════════════════════════════════════════"
echo " ✓ Release built"
echo "   Signed: $SIGN${SIGN_TEAM:+ [team $SIGN_TEAM]}"
echo "   osax:  $ROOT/build/ColumnTamer.osax"
echo "   menu:  $ROOT/build/menubuild/ColumnTamerMenu.app"
echo "══════════════════════════════════════════════════════════"
