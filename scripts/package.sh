#!/bin/zsh
#
# package.sh — ColumnTamer pkg installer (release + stage + notarize).
#   Called by `make package`. Runs release.sh first (chain), then stages
#   payload into .pkg (+notarize if DevID creds).
#
set -eu
cd "$(dirname "$0")/.."
ROOT=$(pwd)

PKG="$ROOT/scripts/package-payload.sh"

# Chain: build + sign Release first.
echo "▸ release.sh →"
scripts/release.sh >/dev/null

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

# Stage signed artifacts into pkg (release.sh already signed).
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
