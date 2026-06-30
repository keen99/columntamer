#!/bin/zsh
#
# run.sh — ColumnTamer dev run. One command = test build end-to-end.
#   Called by `make run`. Build Debug + dev-install osax + launch menu + inject.
#   Does ALL setup itself: no separate install step needed for dev test.
#   sudo-free: osascript admin privileges (native GUI password popup).
#
set -eu
cd "$(dirname "$0")/.."
ROOT=$(pwd)

OSAX_SYS="/Library/ScriptingAdditions/ColumnTamer.osax"

# ── Build (Debug, signs Apple Dev by default) ──────────────────────────────
scripts/build.sh Debug

# ── Dev-install osax so Finder can see it ──────────────────────────────────
# Full install.sh also sets up helper + LaunchAgent; dev test only needs the
# osax on disk for inject to work. Re-copy each run so build changes take hold.
# osascript admin = native GUI password popup (no TTY needed). Built-in popup
# text is Apple-controlled, so preface with an explanatory dialog (the WHY).
echo "▸ Dev-install osax (admin)"
osascript <<ASCRIPT >/dev/null
-- Single clear prompt: WHY + hidden password field. No Apple generic popup.
set resp to display dialog "ColumnTamer dev run (make run) needs your admin password to install the just-built osax into the system path so Finder can load it for testing:

    /Library/ScriptingAdditions/ColumnTamer.osax

Finder only loads scripting additions from that path." default answer "" with title "ColumnTamer — Dev Install" buttons {"Cancel", "Install"} default button "Install" with hidden answer with icon caution
set thePass to text returned of resp

do shell script "rm -rf '/Library/ScriptingAdditions/ColumnTamer.osax' && cp -R '$ROOT/build/ColumnTamer.osax' '/Library/ScriptingAdditions/ColumnTamer.osax' && chown -R root:wheel '/Library/ScriptingAdditions/ColumnTamer.osax'" password thePass with administrator privileges
ASCRIPT

# ── Launch menu app (product = status menu UI) ─────────────────────────────
# Race-safe: kill prior instance, wait, double-kill, open with retry.
echo "▸ Launch menu app"
pkill -x ColumnTamerMenu 2>/dev/null || true
for i in $(seq 1 25); do
  pgrep -x ColumnTamerMenu >/dev/null 2>&1 || break
  sleep 0.2
done
pkill -x ColumnTamerMenu 2>/dev/null || true
sleep 0.3
for i in 1 2 3; do
  if open "$ROOT/build/menubuild/ColumnTamerMenu.app" 2>/dev/null; then break; fi
  sleep 0.5
done

# ── Restart Finder so it picks up new osax ─────────────────────────────
echo "▸ Restart Finder"
killall Finder 2>/dev/null || true
sleep 2
# ── Inject into Finder ─────────────────────────────────────────────────────
# osax now on system path → event resolves.
echo "▸ Inject into Finder"
/usr/bin/osascript -e 'tell application "Finder" to «event CTmrIjct»' 2>&1 || \
  echo "  (inject failed — Finder may need restart: killall Finder)"
