#!/bin/bash
# Uninstall ColumnTamer (osax + helper + menu app + LaunchAgents + logs + prefs).
# Sweeps legacy `com.local.columntamer` labels (pre-rename installs).
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
  columntamer.helper \
  columntamer.menu \
  com.local.columntamer.helper \
  com.local.columntamer.menu; do
  launchctl disable gui/$CONSOLE_UID/$lbl 2>/dev/null || true
  launchctl bootout  gui/$CONSOLE_UID/$lbl 2>/dev/null || true
done

# quit menu app if still running
/usr/bin/killall ColumnTamerMenu 2>/dev/null || true

echo "=== remove files ==="
sudo rm -rf "$OSAX"
sudo rm -rf "$APPROOT"

echo "=== remove LaunchAgent plists ==="
for p in \
  /Library/LaunchAgents/columntamer.helper.plist \
  /Library/LaunchAgents/columntamer.menu.plist \
  /Library/LaunchAgents/com.local.columntamer.helper.plist \
  /Library/LaunchAgents/com.local.columntamer.menu.plist; do
  sudo rm -f "$p"
done
# user-local copies (older dev installs put some here)
for p in \
  ~/Library/LaunchAgents/columntamer.helper.plist \
  ~/Library/LaunchAgents/columntamer.menu.plist \
  ~/Library/LaunchAgents/com.local.columntamer.helper.plist \
  ~/Library/LaunchAgents/com.local.columntamer.menu.plist; do
  rm -f "$p"
done

echo "=== forget pkg receipts + PK bundle registration ==="
# pkgutil --forget clears receipt but PK also cache bundle ID → path mapping.
# Nuke receipt files directly to ensure PK re-register on next install.
sudo rm -f /var/db/receipts/columntamer.* /var/db/receipts/com.local.columntamer.* 2>/dev/null || true
sudo pkgutil --forget columntamer 2>/dev/null || true
sudo pkgutil --forget com.local.columntamer 2>/dev/null || true

echo "=== remove prefs ==="
/usr/bin/defaults delete com.apple.finder ColumnTamerMinWidth 2>/dev/null || true
/usr/bin/defaults delete com.apple.finder ColumnTamerMaxWidth 2>/dev/null || true
/usr/bin/defaults delete com.apple.finder ColumnTamerPreviewWidth 2>/dev/null || true

# clear stale install log
rm -f "$LOG"

echo "=== restart Finder to clear live injection ==="
if /usr/bin/pgrep -x Finder >/dev/null 2>&1; then
  echo "  killing Finder (menubar will blink ~2s)..."
  /usr/bin/killall Finder
  # wait for Finder to relaunch (launchd auto-respawns)
  for i in 1 2 3 4 5; do
    /usr/bin/pgrep -x Finder >/dev/null 2>&1 && break
    /bin/sleep 1
  done
  if /usr/bin/pgrep -x Finder >/dev/null 2>&1; then
    echo "  Finder restarted — osax fully unloaded."
  else
    echo "  ⚠ Finder did not relaunch within 5s. Open a Finder window to trigger it."
  fi
else
  echo "  Finder not running — nothing to restart."
fi

echo
echo "DONE — ColumnTamer removed."
echo "If Finder columns still misbehave, restart Finder manually:"
echo "  killall Finder"
