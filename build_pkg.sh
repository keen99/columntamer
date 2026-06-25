#!/bin/zsh
# Build ColumnTamer osax + menu app, then package as installable .pkg.
# System-wide layout (no user paths):
#   /Library/ScriptingAdditions/ColumnTamer.osax
#   /Library/Application Support/ColumnTamer/ColumnTamerHelper
#   /Library/Application Support/ColumnTamer/ColumnTamerMenu.app
#   /Library/Application Support/ColumnTamer/logs/
#   /Library/LaunchAgents/com.local.columntamer.helper.plist
#   /Library/LaunchAgents/com.local.columntamer.menu.plist
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

echo "=== build menu app ==="
"$ROOT/menu-app/build.sh" >/dev/null

echo "=== stage payload ==="
rm -rf "$STAGE" "$SCRIPTS" "$PKG"
mkdir -p "$STAGE/Library/ScriptingAdditions" \
         "$STAGE/Library/Application Support/ColumnTamer/logs" \
         "$STAGE/Library/LaunchAgents" \
         "$SCRIPTS"

cp -R "$ROOT/build/ColumnTamer.osax" "$STAGE/Library/ScriptingAdditions/ColumnTamer.osax"
cp "$ROOT/ColumnTamerHelper"         "$STAGE/Library/Application Support/ColumnTamer/ColumnTamerHelper"
chmod 755 "$STAGE/Library/Application Support/ColumnTamer/ColumnTamerHelper"
cp -R "$ROOT/build/menubuild/ColumnTamerMenu.app" \
   "$STAGE/Library/Application Support/ColumnTamer/ColumnTamerMenu.app"
cp "$ROOT/com.local.columntamer.helper.plist" \
   "$STAGE/Library/LaunchAgents/com.local.columntamer.helper.plist"
cp "$ROOT/com.local.columntamer.menu.plist" \
   "$STAGE/Library/LaunchAgents/com.local.columntamer.menu.plist"

echo "=== write postinstall ==="
cat > "$SCRIPTS/preinstall" <<'PREINSTALL'
#!/bin/zsh
# preinstall: ask user BEFORE install whether to restart Finder after.
# Runs as root pre-payload. launchctl asuser reaches user's Aqua session.
set -u

FLAG="/tmp/.columntamer.restart-finder"
rm -f "$FLAG" 2>/dev/null || true

CONSOLE_USER="$(/usr/bin/stat -f%Su /dev/console 2>/dev/null || true)"
CONSOLE_UID="$(/usr/bin/id -u "$CONSOLE_USER" 2>/dev/null || true)"
[[ -z "$CONSOLE_UID" ]] && exit 0

RESULT="$(/bin/launchctl asuser "$CONSOLE_UID" /usr/bin/sudo -u "$CONSOLE_USER" /usr/bin/osascript -e '
  return button returned of (display dialog "ColumnTamer will be installed." & return & return & "Restart Finder afterward to activate?" with title "ColumnTamer" buttons {"Later", "Restart After Install"} default button "Restart After Install" with icon note)
' 2>/dev/null || true)"

if [[ "$RESULT" == *"Restart After Install"* ]]; then
  /bin/echo "yes" > "$FLAG"
fi

exit 0
PREINSTALL
chmod 755 "$SCRIPTS/preinstall"

cat > "$SCRIPTS/postinstall" <<'POSTINSTALL'
#!/bin/zsh
# postinstall: bootstrap LaunchAgent + restart Finder if user agreed preinstall.
set -e

OSAX="/Library/ScriptingAdditions/ColumnTamer.osax"
BIN="/Library/Application Support/ColumnTamer/ColumnTamerHelper"
PLIST="/Library/LaunchAgents/com.local.columntamer.helper.plist"
LOGDIR="/Library/Application Support/ColumnTamer/logs"
FLAG="/tmp/.columntamer.restart-finder"

chmod 755 "$BIN"
mkdir -p "$LOGDIR"
chmod 1777 "$LOGDIR"

CONSOLE_USER="$(/usr/bin/stat -f%Su /dev/console 2>/dev/null || true)"
CONSOLE_UID="$(/usr/bin/id -u "$CONSOLE_USER" 2>/dev/null || true)"

# bootstrap helper agent
if [[ -n "$CONSOLE_UID" ]]; then
  /bin/launchctl bootout gui/$CONSOLE_UID "$PLIST" 2>/dev/null || true
  /bin/launchctl bootstrap gui/$CONSOLE_UID "$PLIST"
  /bin/launchctl enable gui/$CONSOLE_UID/com.local.columntamer.helper
  /bin/launchctl kickstart -k gui/$CONSOLE_UID/com.local.columntamer.helper
fi

# launch menu app via its own LaunchAgent (launchd-managed).
# Start-at-login checkbox reads launchctl list -> default ON after install.
MENU_PLIST="/Library/LaunchAgents/com.local.columntamer.menu.plist"
if [[ -n "$CONSOLE_UID" ]]; then
  /bin/launchctl bootout gui/$CONSOLE_UID "$MENU_PLIST" 2>/dev/null || true
  /bin/launchctl bootstrap gui/$CONSOLE_UID "$MENU_PLIST"
  /bin/launchctl enable gui/$CONSOLE_UID/com.local.columntamer.menu
  /bin/launchctl kickstart -k gui/$CONSOLE_UID/com.local.columntamer.menu
fi

# restart only if user agreed at preinstall prompt
if [[ -f "$FLAG" ]]; then
  /usr/bin/killall Finder 2>/dev/null || true
  rm -f "$FLAG"
else
  if [[ -n "$CONSOLE_UID" ]]; then
    /bin/launchctl asuser "$CONSOLE_UID" /usr/bin/sudo -u "$CONSOLE_USER" /usr/bin/osascript -e \
      'display notification "ColumnTamer installed. Restart Finder to activate." with title "ColumnTamer"' \
      2>/dev/null || true
  fi
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
