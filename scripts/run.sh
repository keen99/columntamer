#!/bin/zsh
#
# run.sh — ColumnTamer dev run. Build Debug + inject into Finder.
#   Called by `make run`. Calls scripts/build.sh (Debug, timed).
#   osax must be installed in /Library/ScriptingAdditions first (make install).
#
set -eu
cd "$(dirname "$0")/.."

# Build (Debug, signs Apple Dev by default).
scripts/build.sh Debug

echo "▸ Dev inject (osascript event)"
/usr/bin/osascript -e 'tell application "Finder" to «event CTmrIjct»' 2>&1 || \
  echo "  (inject failed — osax not in /Library/ScriptingAdditions? run 'make install' once)"
