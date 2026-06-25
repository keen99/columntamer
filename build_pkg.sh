#!/bin/zsh
# Build ColumnTamer osax, then package as installable .pkg.
# System-wide layout (no user paths):
#   /Library/ScriptingAdditions/ColumnTamer.osax
#   /Library/Application Support/ColumnTamer/ColumnTamerHelper
#   /Library/Application Support/ColumnTamer/logs/
#   /Library/LaunchAgents/com.local.columntamer.helper.plist
set -eu

cd "$(dirname "$0")"
ROOT=$(pwd)
STAGE="$ROOT/build/pkgroot"
SCRIPTS="$ROOT/build/pkgscripts"
IDENTIFIER="com.local.columntamer"
VERSION="0.1.0"
PKG="$ROOT/build/ColumnTamer-$VERSION.pkg"

echo "=== build osax first ==="
"$ROOT/build.sh" >/dev/null

echo "=== stage payload ==="
rm -rf "$STAGE" "$SCRIPTS" "$PKG"
mkdir -p "$STAGE/Library/ScriptingAdditions" \
         "$STAGE/Library/Application Support/ColumnTamer/logs" \
         "$STAGE/Library/LaunchAgents" \
         "$SCRIPTS"

cp -R "$ROOT/build/ColumnTamer.osax" "$STAGE/Library/ScriptingAdditions/ColumnTamer.osax"
cp "$ROOT/ColumnTamerHelper"         "$STAGE/Library/Application Support/ColumnTamer/ColumnTamerHelper"
chmod 755 "$STAGE/Library/Application Support/ColumnTamer/ColumnTamerHelper"
cp "$ROOT/com.local.columntamer.helper.plist" \
   "$STAGE/Library/LaunchAgents/com.local.columntamer.helper.plist"

echo "=== write postinstall ==="
cat > "$SCRIPTS/postinstall" <<'POSTINSTALL'
#!/bin/zsh
# postinstall: bootstrap LaunchAgent. Helper auto-injects on poll (~5s).
# No osascript here — avoids TCC Automation prompt.
set -e

OSAX="/Library/ScriptingAdditions/ColumnTamer.osax"
BIN="/Library/Application Support/ColumnTamer/ColumnTamerHelper"
PLIST="/Library/LaunchAgents/com.local.columntamer.helper.plist"
LOGDIR="/Library/Application Support/ColumnTamer/logs"

chmod 755 "$BIN"
mkdir -p "$LOGDIR"
chmod 1777 "$LOGDIR"

CONSOLE_USER="$(/usr/bin/stat -f%Su /dev/console 2>/dev/null || true)"
if [[ -n "$CONSOLE_USER" ]]; then
  CONSOLE_UID="$(/usr/bin/id -u "$CONSOLE_USER")"
  /bin/launchctl bootout gui/$CONSOLE_UID "$PLIST" 2>/dev/null || true
  /bin/launchctl bootstrap gui/$CONSOLE_UID "$PLIST"
  /bin/launchctl enable gui/$CONSOLE_UID/com.local.columntamer.helper
  /bin/launchctl kickstart -k gui/$CONSOLE_UID/com.local.columntamer.helper
fi

# unattended: kill Finder so osax loads fresh + ColumnTamer activates now.
# helper auto-injects on Finder relaunch (~5s). notify user.
/usr/bin/killall Finder 2>/dev/null || true
if [[ -n "$CONSOLE_USER" ]]; then
  /bin/sleep 2
  /usr/bin/sudo -u "$CONSOLE_USER" /usr/bin/osascript -e \
    'display notification "ColumnTamer installed. Finder restarted to activate." with title "ColumnTamer"' \
    2>/dev/null || true
fi

exit 0
POSTINSTALL
chmod 755 "$SCRIPTS/postinstall"

echo "=== build pkg ==="
pkgbuild \
  --root "$STAGE" \
  --scripts "$SCRIPTS" \
  --identifier "$IDENTIFIER" \
  --version "$VERSION" \
  --ownership recommended \
  "$PKG"

echo "=== verify pkg ==="
pkgutil --check-signature "$PKG" 2>&1 || echo "(unsigned — ok, SIP off path)"
echo "payload:"
pkgutil --payload-files "$PKG" | sed 's/^/  /'

echo "=== DONE ==="
echo "pkg: $PKG"
echo "install: sudo installer -pkg \"$PKG\" -target /"
