#!/bin/zsh
#
# dev.sh — ColumnTamer Debug build (osax + menu) + optional inject.
#   Called by `make build` / `make run`.
#   Signing identity from SIGN_IDENTITY env (Makefile auto-detects Apple Dev).
#
set -eu
cd "$(dirname "$0")/.."
ROOT=$(pwd)

LAUNCH=0
[[ "${1:-}" == "--launch" ]] && LAUNCH=1

echo "▸ Building osax (Debug)"
"$ROOT/build.sh" >/dev/null

echo "▸ Building menu app (Debug)"
"$ROOT/menu-app/build.sh" >/dev/null

OSAX="$ROOT/build/ColumnTamer.osax"
echo "▸ Signed: ${SIGN_IDENTITY:--}${SIGN_TEAM:+ [team $SIGN_TEAM]}"
echo "▸ osax:  $OSAX"
echo "▸ menu:  $ROOT/build/menubuild/ColumnTamerMenu.app"

if [[ "$LAUNCH" -eq 1 ]]; then
  echo "▸ Dev inject (osascript event)"
  /usr/bin/osascript -e 'tell application "Finder" to «event CTmrIjct»' 2>&1 || \
    echo "  (inject failed — osax not in /Library/ScriptingAdditions? run 'make install' once)"
fi
