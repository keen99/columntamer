#!/bin/zsh
# Install XPLock osax + reinject LaunchAgent. Run once after build.
set -eu
cd "$(dirname "$0")"
BUNDLE="$PWD/build/XPLock.osax"
OSAX_DST="/Library/ScriptingAdditions/XPLock.osax"
BIN="$HOME/.local/bin/xplock-reinject"
PLIST="$HOME/Library/LaunchAgents/com.local.xplock-reinject.plist"

echo "=== install osax (sudo) ==="
sudo -v
sudo rm -rf "$OSAX_DST"
sudo cp -R "$BUNDLE" "$OSAX_DST"
sudo chown -R root:wheel "$OSAX_DST"

echo "=== install watcher bin ==="
mkdir -p "$(dirname "$BIN")"
cp xplock-reinject "$BIN"
chmod 755 "$BIN"

echo "=== install launchagent ==="
mkdir -p "$(dirname "$PLIST")"
cp com.local.xplock-reinject.plist "$PLIST"

echo "=== validate ==="
plutil -lint "$PLIST"
codesign -dv "$OSAX_DST/Contents/MacOS/XPLock" 2>&1 | grep -i identifier || echo "unsigned (ok, libvalidation off)"

echo "=== bootstrap agent ==="
UIDU="$(id -u)"
launchctl bootout gui/$UIDU "$PLIST" 2>/dev/null || true
launchctl bootstrap gui/$UIDU "$PLIST"
launchctl enable gui/$UIDU/com.local.xplock-reinject
launchctl kickstart -k gui/$UIDU/com.local.xplock-reinject

echo "=== initial inject into running Finder ==="
sleep 3
/usr/bin/osascript -e 'tell application "Finder" to inject' 2>&1 || echo "(Finder may need restart)"

echo
echo "DONE"
echo "osax:   $OSAX_DST"
echo "agent:  $PLIST"
echo "verify: log show --predicate 'process == \"Finder\"' --last 1m --info | grep XPLock"
echo
echo "tune width: defaults write com.apple.finder XPLockPreviewWidth -float 400 ; then restart Finder"
