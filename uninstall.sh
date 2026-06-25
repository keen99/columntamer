#!/bin/zsh
# Uninstall ColumnTamer (osax + helper + menu app + LaunchAgents + logs + prefs).
# Also sweeps legacy XPLock-named artifacts from early dev versions.
set -eu

OSAX="/Library/ScriptingAdditions/ColumnTamer.osax"
APPROOT="/Library/Application Support/ColumnTamer"
MENU_APP="/Library/Application Support/ColumnTamer/ColumnTamerMenu.app"
LOG="/tmp/columntamer-postinstall.log"

CONSOLE_USER="$(/usr/bin/stat -f%Su /dev/console 2>/dev/null || echo "$USER")"
CONSOLE_UID="$(/usr/bin/id -u "$CONSOLE_USER")"

echo "=== stop agents (current + legacy labels) ==="
# disable (clear login flag) then bootout (unload). bootout runs as user (user domain).
for lbl in \
  com.local.columntamer.helper \
  com.local.columntamer.menu \
  com.local.xplock.helper \
  com.local.xplock-reinject; do
  launchctl disable gui/$CONSOLE_UID/$lbl 2>/dev/null || true
  launchctl bootout  gui/$CONSOLE_UID/$lbl 2>/dev/null || true
done

# quit menu app if still running
/usr/bin/killall ColumnTamerMenu 2>/dev/null || true

echo "=== remove files ==="
sudo rm -rf "$OSAX"
sudo rm -rf "$APPROOT"
# legacy paths from dev versions
sudo rm -rf /Library/ScriptingAdditions/XPLock.osax
sudo rm -rf "/Library/Application Support/XPLock"
sudo rm -f /tmp/.columntamer.restart-finder

echo "=== remove LaunchAgent plists ==="
for p in \
  /Library/LaunchAgents/com.local.columntamer.helper.plist \
  /Library/LaunchAgents/com.local.columntamer.menu.plist \
  /Library/LaunchAgents/com.local.xplock.helper.plist \
  /Library/LaunchAgents/com.local.xplock-reinject.plist; do
  sudo rm -f "$p"
done
# user-local copies (older dev installs put some here)
for p in \
  ~/Library/LaunchAgents/com.local.columntamer.helper.plist \
  ~/Library/LaunchAgents/com.local.columntamer.menu.plist \
  ~/Library/LaunchAgents/com.local.xplock.helper.plist \
  ~/Library/LaunchAgents/com.local.xplock-reinject.plist; do
  rm -f "$p"
done
rm -f ~/.local/bin/xplock-reinject
# per-user helper logs (M7: moved out of /Library)
rm -rf ~/Library/Logs/ColumnTamer
rm -f ~/.columntamer.menu.lock

echo "=== forget pkg receipts ==="
sudo pkgutil --forget com.local.columntamer 2>/dev/null || true
sudo pkgutil --forget com.local.xplock 2>/dev/null || true

echo "=== remove prefs ==="
/usr/bin/defaults delete com.apple.finder ColumnTamerMinWidth 2>/dev/null || true
/usr/bin/defaults delete com.apple.finder ColumnTamerMaxWidth 2>/dev/null || true
/usr/bin/defaults delete com.apple.finder ColumnTamerPreviewWidth 2>/dev/null || true
/usr/bin/defaults delete com.apple.finder XPLockPreviewWidth 2>/dev/null || true

# clear stale install log
rm -f "$LOG"

echo "=== restart Finder to clear live injection ==="
/usr/bin/killall Finder 2>/dev/null || true

echo
echo "DONE — ColumnTamer removed."
