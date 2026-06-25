#!/bin/zsh
# Uninstall ColumnTamer (osax + helper + LaunchAgent + logs).
# Also removes legacy XPLock-named artifacts from prior versions.
set -eu

OSAX="/Library/ScriptingAdditions/ColumnTamer.osax"
APPROOT="/Library/Application Support/ColumnTamer"
PLIST="/Library/LaunchAgents/com.local.columntamer.helper.plist"

echo "=== stop LaunchAgent (current + legacy labels) ==="
CONSOLE_USER="$(/usr/bin/stat -f%Su /dev/console 2>/dev/null || echo "$USER")"
CONSOLE_UID="$(/usr/bin/id -u "$CONSOLE_USER")"
for lbl in com.local.columntamer.helper com.local.xplock.helper com.local.xplock-reinject; do
  sudo launchctl bootout gui/$CONSOLE_UID/$lbl 2>/dev/null || true
done
for p in \
  /Library/LaunchAgents/com.local.columntamer.helper.plist \
  /Library/LaunchAgents/com.local.xplock.helper.plist \
  /Library/LaunchAgents/com.local.xplock-reinject.plist; do
  sudo launchctl bootout gui/$CONSOLE_UID "$p" 2>/dev/null || true
done

echo "=== remove files ==="
sudo rm -rf "$OSAX"
sudo rm -rf "$APPROOT"
# legacy paths
sudo rm -rf /Library/ScriptingAdditions/XPLock.osax
sudo rm -rf "/Library/Application Support/XPLock"
sudo rm -f "$PLIST"
sudo rm -f /Library/LaunchAgents/com.local.xplock.helper.plist
sudo rm -f /Library/LaunchAgents/com.local.xplock-reinject.plist
rm -f ~/Library/LaunchAgents/com.local.columntamer.helper.plist
rm -f ~/Library/LaunchAgents/com.local.xplock.helper.plist
rm -f ~/Library/LaunchAgents/com.local.xplock-reinject.plist
rm -f ~/.local/bin/xplock-reinject

echo "=== forget pkg receipts ==="
sudo pkgutil --forget com.local.columntamer 2>/dev/null || true
sudo pkgutil --forget com.local.xplock 2>/dev/null || true

echo "=== remove prefs (optional) ==="
/usr/bin/defaults delete com.apple.finder ColumnTamerPreviewWidth 2>/dev/null || true
/usr/bin/defaults delete com.apple.finder XPLockPreviewWidth 2>/dev/null || true

/usr/bin/killall Finder 2>/dev/null || true

echo
echo "DONE — ColumnTamer removed. Finder restarted to clear live injection."
