#!/bin/zsh
#
# package.sh — ColumnTamer pkg installer (builds + signs + notarizes).
#   Called by `make package`. Smart-sign inside. Runs payload builder.
#
set -eu
cd "$(dirname "$0")/.."
ROOT=$(pwd)

PKG="$ROOT/scripts/package-payload.sh"

# Smart-pick identity, export to payload builder.
if [[ -n "${DEVELOPER_IDENTITY:-}" ]]; then
  SIGN="$DEVELOPER_IDENTITY"
  SIGN_TEAM="${APPLE_TEAM_ID:-}"
elif security find-identity -v -p codesigning 2>/dev/null | grep -q "Apple Development"; then
  SIGN="$(security find-identity -v -p codesigning | grep "Apple Development" | head -1 | sed 's/.*"\(.*\)".*/\1/')"
  SIGN_TEAM="$(security find-certificate -c "Apple Development" -p 2>/dev/null \
    | openssl x509 -noout -subject 2>/dev/null | grep -oE 'OU=[A-Z0-9]+' | cut -d= -f2)"
else
  SIGN="-"
  SIGN_TEAM=""
fi
export SIGN_IDENTITY="$SIGN"
export SIGN_TEAM

# Decide notarize (pkg-level, after build).
NOTARIZE=0
if [[ -n "${DEVELOPER_IDENTITY:-}" \
   && -n "${APPLE_ID:-}" \
   && -n "${APPLE_TEAM_ID:-}" \
   && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]]; then
  NOTARIZE=1
  echo "▸ Notarize: yes (Developer ID creds present)"
else
  echo "▸ Notarize: skipped (some creds unset). pkg unsigned — Gatekeeper warns for others."
fi

# Build payload + artifacts (signs osax/menu with SIGN_IDENTITY).
"$PKG"

# Locate produced pkg.
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
PKGFILE="$ROOT/build/ColumnTamer-$VERSION.pkg"
[[ -f "$PKGFILE" ]] || { echo "✗ pkg not found: $PKGFILE"; exit 1; }

# Sign + notarize the pkg itself (separate from artifacts).
if [[ "$NOTARIZE" -eq 1 ]]; then
  echo "▸ Signing pkg with Developer ID Installer: ${DEVELOPER_IDENTITY_INSTALLER:-$DEVELOPER_IDENTITY}"
  productsign --sign "${DEVELOPER_IDENTITY_INSTALLER:-$DEVELOPER_IDENTITY}" "$PKGFILE" "$PKGFILE.signed"
  mv "$PKGFILE.signed" "$PKGFILE"

  echo "▸ Notarizing pkg…"
  xcrun notarytool submit "$PKGFILE" \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_SPECIFIC_PASSWORD" \
    --wait
  echo "▸ Stapling ticket"
  xcrun stapler staple "$PKGFILE"
fi

echo
echo "══════════════════════════════════════════════════════════"
echo " ✓ Packaged $VERSION"
if [[ "$NOTARIZE" -eq 1 ]]; then echo "   Notarized + stapled"
else echo "   Unsigned pkg (not notarized)"; fi
echo "   pkg: $PKGFILE"
echo "   install: sudo installer -pkg \"$PKGFILE\" -target /"
echo "══════════════════════════════════════════════════════════"
