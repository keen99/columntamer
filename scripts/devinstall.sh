#!/bin/bash
# Local install (no pkg) — osax + menu app + LaunchAgent.
# Menu in /Applications (user-launchable). osax in /Library/ScriptingAdditions.
set -eu
cd "$(dirname "$0")"

OSAX="/Library/ScriptingAdditions/ColumnTamer.osax"
MENU_APP="/Applications/ColumnTamer.app"
MENU_LEGACY="/Applications/ColumnTamerMenu.app"
LEGACY_APPROOT="/Library/Application Support/ColumnTamer"
MENU_PLIST="/Library/LaunchAgents/columntamer.menu.plist"
UIDU="$(id -u)"

echo "=== stop old agents ==="
# Sweep legacy helper (pre-fold installs shipped shell helper + LaunchAgent).
launchctl bootout gui/$UIDU/columntamer.helper 2>/dev/null || true
sudo rm -f "/Library/LaunchAgents/columntamer.helper.plist" 2>/dev/null || true
pkill -f "ColumnTamerHelper" 2>/dev/null || true
pkill -f "ColumnTamer" 2>/dev/null || true
# legacy dev-run menu (pre-rename build path)
pkill -f "build/menubuild/ColumnTamerMenu" 2>/dev/null || true
launchctl bootout gui/$UIDU/columntamer.menu 2>/dev/null || true

echo "=== install osax (sudo) ==="
sudo -v
sudo rm -rf "$OSAX"
sudo cp -R ../build/ColumnTamer.osax "$OSAX"
sudo chown -R root:wheel "$OSAX"
# signed by build step; do NOT re-sign ad-hoc (breaks Finder load)

echo "=== install menu app ==="
sudo rm -rf "$MENU_APP"
sudo cp -R ../build/menubuild/ColumnTamer.app "$MENU_APP"
sudo chown -R root:wheel "$MENU_APP"
# signed by build step; do NOT re-sign ad-hoc

echo "=== remove legacy menu (pre-rename) + approot (pre-rehome) ==="
sudo rm -rf "$MENU_LEGACY"
sudo rm -rf "$LEGACY_APPROOT"

echo "=== install LaunchAgent ==="
sudo cp ../columntamer.menu.plist "$MENU_PLIST"
plutil -lint "$MENU_PLIST" >/dev/null

echo "=== bootstrap menu agent ==="
# NOTE: bootstrap gui/$UID may fail from root (EIO in sandbox).
# OK — plists installed, launchd pick up on next login.
sudo launchctl bootstrap gui/$UIDU "$MENU_PLIST" || echo "  (bootstrap deferred — will load at next login)"

echo "=== launch menu app ==="
open "$MENU_APP" || echo "  (open failed)"

echo "=== restart Finder to load osax ==="
echo "  osax constructor runs at Finder launch. Kill Finder to reload."
sudo killall Finder || true
echo "  Finder restarting — osax should load automatically."

echo
echo "DONE"
echo "osax: $OSAX"
echo "menu: $MENU_APP"
echo "verify: log show --predicate 'process==\"Finder\"' --last 1m --info | grep ColumnTamer"
