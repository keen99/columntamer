#!/bin/bash
# Build ColumnTamer osax + menu app, then package as installable .pkg.
# System-wide layout (no user paths):
#   /Library/ScriptingAdditions/ColumnTamer.osax
#   /Library/Application Support/ColumnTamer/ColumnTamerHelper
#   /Library/Application Support/ColumnTamer/ColumnTamerMenu.app
#   /Library/Application Support/ColumnTamer/logs/
#   /Library/LaunchAgents/columntamer.helper.plist
#   /Library/LaunchAgents/columntamer.menu.plist
set -eu

cd "$(dirname "$0")/.."
ROOT=$(pwd)
STAGE="$ROOT/build/pkgroot"
SCRIPTS="$ROOT/build/pkgscripts"
IDENTIFIER="columntamer"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
BUILD_NUM="$(cd "$ROOT" && git rev-list --count HEAD 2>/dev/null || echo 1)"
PKG="$ROOT/build/ColumnTamer-$VERSION.pkg"

echo "=== stage payload ==="
rm -rf "$STAGE" "$SCRIPTS" "$PKG"
mkdir -p "$STAGE/Library/ScriptingAdditions" \
         "$STAGE/Library/Application Support/ColumnTamer" \
         "$STAGE/Library/LaunchAgents" \
         "$SCRIPTS"

cp -R "$ROOT/build/ColumnTamer.osax" "$STAGE/Library/ScriptingAdditions/ColumnTamer.osax"
cp "$ROOT/ColumnTamerHelper"         "$STAGE/Library/Application Support/ColumnTamer/ColumnTamerHelper"
chmod 755 "$STAGE/Library/Application Support/ColumnTamer/ColumnTamerHelper"
cp -R "$ROOT/build/menubuild/ColumnTamerMenu.app" \
   "$STAGE/Library/Application Support/ColumnTamer/ColumnTamerMenu.app"
cp "$ROOT/columntamer.helper.plist" \
   "$STAGE/Library/LaunchAgents/columntamer.helper.plist"
cp "$ROOT/columntamer.menu.plist" \
   "$STAGE/Library/LaunchAgents/columntamer.menu.plist"

echo "=== write postinstall ==="
cat > "$SCRIPTS/preinstall" <<'PREINSTALL'
#!/bin/zsh
# preinstall: ask user BEFORE install whether to restart Finder after.
# Runs as root pre-payload. launchctl asuser reaches user's Aqua session.
set -u

FLAG="/var/run/.columntamer.restart"
rm -f "$FLAG" 2>/dev/null || true

CONSOLE_USER="$(/usr/bin/stat -f%Su /dev/console 2>/dev/null || true)"
CONSOLE_UID="$(/usr/bin/id -u "$CONSOLE_USER" 2>/dev/null || true)"
[[ -z "$CONSOLE_UID" ]] && exit 0

# Native installer context: COMMAND_LINE_INSTALL=1 -> CLI `installer` binary.
# Unset -> GUI Installer.app. CLI = unattended: skip dialog, default restart.
if [[ "${COMMAND_LINE_INSTALL:-0}" == "1" ]]; then
  /bin/echo "yes" > "$FLAG"
  exit 0
fi

RESULT="$(/bin/launchctl asuser "$CONSOLE_UID" /usr/bin/sudo -u "$CONSOLE_USER" /usr/bin/osascript -e '
  return button returned of (display dialog "ColumnTamer will be installed." & return & return & "Restart Finder afterward to activate?" with title "ColumnTamer" buttons {"Later", "Restart After Install"} default button "Restart After Install" with icon note giving up after 300)
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

BIN="/Library/Application Support/ColumnTamer/ColumnTamerHelper"
HELPER_PLIST="/Library/LaunchAgents/columntamer.helper.plist"
MENU_PLIST="/Library/LaunchAgents/columntamer.menu.plist"
FLAG="/var/run/.columntamer.restart"

chmod 755 "$BIN"

# M7: remove stale shared logdir from older installs (was 1777 symlink trap).
# Logs now per-user at ~/Library/Logs/ColumnTamer/.
rm -rf "/Library/Application Support/ColumnTamer/logs"

# M6: pin ownership to root:wheel (installer runs as root; staged files
# otherwise may carry dev-user ownership = persistence vector).
chown -R root:wheel "/Library/ScriptingAdditions/ColumnTamer.osax"
chown -R root:wheel "/Library/Application Support/ColumnTamer"
chown root:wheel "$HELPER_PLIST" "$MENU_PLIST"

CONSOLE_USER="$(/usr/bin/stat -f%Su /dev/console 2>/dev/null || true)"
CONSOLE_UID="$(/usr/bin/id -u "$CONSOLE_USER" 2>/dev/null || true)"

# bootstrap agents AS USER. RunAtLoad=true auto-launches; no kickstart (blocks).
# bootstrap runs backgrounded so postinstall returns fast.
if [[ -n "$CONSOLE_UID" ]]; then
  /usr/bin/sudo -u "$CONSOLE_USER" /bin/launchctl bootout gui/$CONSOLE_UID "$HELPER_PLIST" 2>/dev/null || true
  /usr/bin/sudo -u "$CONSOLE_USER" /bin/launchctl bootout gui/$CONSOLE_UID/columntamer.menu 2>/dev/null || true
  /usr/bin/sudo -u "$CONSOLE_USER" /bin/launchctl bootout gui/$CONSOLE_UID "$MENU_PLIST" 2>/dev/null || true
  /usr/bin/killall ColumnTamerMenu 2>/dev/null || true
  /usr/bin/sudo -u "$CONSOLE_USER" /bin/launchctl bootstrap gui/$CONSOLE_UID "$HELPER_PLIST" &
  /usr/bin/sudo -u "$CONSOLE_USER" /bin/launchctl bootstrap gui/$CONSOLE_UID "$MENU_PLIST" &
fi

# restart only if user agreed at preinstall prompt
if [[ -f "$FLAG" ]]; then
  /usr/bin/killall Finder 2>/dev/null || true
  rm -f "$FLAG"
else
  if [[ -n "$CONSOLE_UID" ]]; then
    /usr/bin/sudo -u "$CONSOLE_USER" /usr/bin/osascript -e \
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
