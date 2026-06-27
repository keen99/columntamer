#!/bin/zsh
# Local install (no pkg). For dev/testing. Same layout as the pkg.
set -eu
cd "$(dirname "$0")"

OSAX="/Library/ScriptingAdditions/ColumnTamer.osax"
APPROOT="/Library/Application Support/ColumnTamer"
PLIST="/Library/LaunchAgents/columntamer.helper.plist"

echo "=== install osax (sudo) ==="
sudo -v
sudo rm -rf "$OSAX"
sudo cp -R build/ColumnTamer.osax "$OSAX"
sudo chown -R root:wheel "$OSAX"
sudo codesign --force --sign - "$OSAX"

echo "=== install helper ==="
sudo mkdir -p "$APPROOT/logs"
sudo cp ColumnTamerHelper "$APPROOT/ColumnTamerHelper"
sudo chmod 755 "$APPROOT/ColumnTamerHelper"
sudo chmod 1777 "$APPROOT/logs"

echo "=== install launchagent ==="
sudo cp columntamer.helper.plist "$PLIST"

echo "=== validate ==="
plutil -lint "$PLIST"
codesign -dv "$OSAX" 2>&1 | grep -E "Identifier|Signature"

echo "=== bootstrap agent ==="
UIDU="$(id -u)"
launchctl bootout gui/$UIDU "$PLIST" 2>/dev/null || true
sudo launchctl bootstrap gui/$UIDU "$PLIST"
sudo launchctl enable gui/$UIDU/columntamer.helper
sudo launchctl kickstart -k gui/$UIDU/columntamer.helper

echo "=== initial inject ==="
sleep 3
/usr/bin/osascript -e 'tell application "Finder" to «event CTmrIjct»' 2>&1 || echo "(Finder may need restart)"

echo
echo "DONE"
echo "osax:  $OSAX"
echo "agent: $PLIST"
echo "verify: log show --predicate 'process == \"Finder\"' --last 1m --info | grep ColumnTamer"
