#!/bin/zsh
#
# release.sh — ColumnTamer release. Build Release + smart-sign.
#   Called by `make release`. Calls scripts/build.sh Release (timed).
#   No pkg, no notarize. For distribution run `make package`.
#
set -eu
cd "$(dirname "$0")/.."
ROOT=$(pwd)

scripts/build.sh Release

echo "▸ Signature check"
codesign -dv "$ROOT/build/ColumnTamer.osax" 2>&1 | grep -E "Identifier|Signature|TeamIdentifier"
codesign -dv "$ROOT/build/menubuild/ColumnTamerMenu.app" 2>&1 | grep -E "Identifier|Signature|TeamIdentifier"

echo
echo "══════════════════════════════════════════════════════════"
echo " ✓ Release built"
echo "   Run 'make package' for .pkg installer"
echo "══════════════════════════════════════════════════════════"
