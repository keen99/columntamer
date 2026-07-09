#!/bin/bash
# Local install (no pkg) — osax + helper + menu app + LaunchAgents.
# Same layout as pkg. For dev/testing.
set -eu
cd "$(dirname "$0")"

OSAX="/Library/ScriptingAdditions/ColumnTamer.osax"
APPROOT="/Library/Application Support/ColumnTamer"
MENU_APP="$APPROOT/ColumnTamerMenu.app"
HELPER_PLIST="/Library/LaunchAgents/columntamer.helper.plist"
MENU_PLIST="/Library/LaunchAgents/columntamer.menu.plist"
UIDU="$(id -u)"

echo "=== stop old agents ==="
launchctl bootout gui/$UIDU/columntamer.helper 2>/dev/null || true
launchctl bootout gui/$UIDU/columntamer.menu 2>/dev/null || true
/usr/bin/killall ColumnTamerMenu 2>/dev/null || true

echo "=== install osax (sudo) ==="
sudo -v
sudo rm -rf "$OSAX"
sudo cp -R ../build/ColumnTamer.osax "$OSAX"
sudo chown -R root:wheel "$OSAX"
# signed by build step; do NOT re-sign ad-hoc (breaks Finder load)

echo "=== install helper ==="
sudo mkdir -p "$APPROOT"
sudo cp ../ColumnTamerHelper "$APPROOT/ColumnTamerHelper"
sudo chmod 755 "$APPROOT/ColumnTamerHelper"

echo "=== install menu app ==="
sudo rm -rf "$MENU_APP"
sudo cp -R ../build/menubuild/ColumnTamerMenu.app "$MENU_APP"
sudo chown -R root:wheel "$MENU_APP"
# signed by build step; do NOT re-sign ad-hoc

echo "=== install LaunchAgents ==="
sudo cp ../columntamer.helper.plist "$HELPER_PLIST"
sudo cp ../columntamer.menu.plist "$MENU_PLIST"
plutil -lint "$HELPER_PLIST" >/dev/null
plutil -lint "$MENU_PLIST" >/dev/null

echo "=== bootstrap agents ==="
# NOTE: bootstrap gui/$UID may fail from root (EIO in sandbox).
# That is OK — plists installed, launchd pick up on next login.
for plist in "$HELPER_PLIST" "$MENU_PLIST"; do
  sudo launchctl bootstrap gui/$UIDU "$plist" || echo "  (bootstrap deferred — will load at next login)"
done
sudo launchctl kickstart -k gui/$UIDU/columntamer.helper || echo "  (kickstart deferred)"

echo "=== launch menu app ==="
open "$MENU_APP" || echo "  (open failed)"

echo "=== restart Finder to load osax ==="
echo "  osax constructor runs at Finder launch. Kill Finder to reload."
sudo /usr/bin/killall Finder || true
echo "  Finder restarting — osax should load automatically."

echo
echo "DONE"
echo "osax:  $OSAX"
echo "helper: $APPROOT/ColumnTamerHelper"
echo "menu:  $MENU_APP"
echo "verify: log show --predicate 'process==\"Finder\"' --last 1m --info | grep ColumnTamer"
