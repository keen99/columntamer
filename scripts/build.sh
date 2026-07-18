#!/bin/bash
#
# build.sh — ColumnTamer core. One engine, 4 doors.
#   Usage: scripts/build.sh [run|build|release|package]   (default run)
#
#   Called by `make run|build|release|package`.
#   NO chain. NO >/dev/null. Output flows straight to user (timestamped).
#   Leaf builders (build-osax.sh, menu-app/build.sh) produce UNSIGNED; signing
#   centralized here for timing visibility.
#
#   Timestamper via FIFO: no subshell, exit code honest, flush on EXIT trap.
#
set -e
cd "$(dirname "$0")/.."
ROOT=$(pwd)

# ── Timestamper (FIFO: current shell, honest exit, flush on exit) ───────────
SECONDS=0
_FIFO=$(mktemp -u); mkfifo "$_FIFO"
while IFS= read -r _l; do printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S') [${SECONDS}s]" "$_l"; done < "$_FIFO" &
_TS_PID=$!
_ts_cleanup() {
  exec >&- 2>&-            # close FIFO write end → reader hits EOF
  wait "$_TS_PID"          # flush remaining lines before exit
  rm -f "$_FIFO"
}
trap _ts_cleanup EXIT
exec > "$_FIFO" 2>&1

MODE="${1:-run}"

# ── Shared metadata ────────────────────────────────────────────────────────
[[ -f VERSION ]] || { echo "✗ VERSION missing"; exit 1; }
VERSION="$(tr -d '[:space:]' < VERSION)"
GIT_COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo dev)"
GIT_BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo dev)"
BUILD_DATE="$(date -u '+%Y-%m-%d %H:%M UTC')"
# Build # = persisted counter (BUILD_NUMBER file = last used, tracked in git).
# Read N, stamp N as this build's #, then bump file to N+1 for next build.
BUILD_NUM_FILE="$ROOT/BUILD_NUMBER"
BUILD_NUM="$(tr -d '[:space:]' < "$BUILD_NUM_FILE" 2>/dev/null || echo 0)"
printf '%s\n' "$((BUILD_NUM + 1))" > "$BUILD_NUM_FILE"
# Dirty = uncommitted changes (excl BUILD_NUMBER which we just bumped).
# Commit hash-dirty = enough trace. Build # stays clean integer.
if ! git diff --quiet -- . ':!BUILD_NUMBER' || ! git diff --cached --quiet -- . ':!BUILD_NUMBER'; then
  GIT_COMMIT="${GIT_COMMIT}-dirty"
fi
echo "▸ Version $VERSION (build $BUILD_NUM, commit $GIT_COMMIT, mode=$MODE)"

OSAX="$ROOT/build/ColumnTamer.osax"
MENU="$ROOT/build/menubuild/ColumnTamerMenu.app"
OSAX_SYS="/Library/ScriptingAdditions/ColumnTamer.osax"

# ── do_build <Debug|Release>: compile leaves + stamp + sign ────────────────
do_build() {
  local config="$1"
  local sign hardsign disp_ver
  # Pick identity: Release+DevID → hardened; else Apple Dev; else ad-hoc.
  if [[ "$config" == "Release" && -n "${DEVELOPER_IDENTITY:-}" ]]; then
    sign="$DEVELOPER_IDENTITY"; hardsign=(-o runtime --timestamp)
  elif security find-identity -v -p codesigning 2>/dev/null | grep -q "Apple Development"; then
    sign="$(security find-identity -v -p codesigning | grep "Apple Development" | head -1 | sed 's/.*"\(.*\)".*/\1/')"
    hardsign=()
  else
    sign="-"; hardsign=()
  fi

  # Debug mangles commit into version (Finder Get Info); Release clean.
  disp_ver="$VERSION"
  [[ "$config" == "Debug" ]] && disp_ver="${VERSION}+${GIT_COMMIT}"

  # Compile leaves (output VISIBLE — no suppression).
  local t0 t1 t2 t3
  t0=$(date +%s)
  echo "▸ Building $config (osax + menu)"
  "$ROOT/build-osax.sh"
  "$ROOT/menu-app/build.sh"
  t1=$(date +%s)

  # Stamp Info.plist copies (source immutable).
  for p in "$OSAX/Contents/Info.plist" "$MENU/Contents/Info.plist"; do
    [[ -f "$p" ]] || continue
    /usr/libexec/PlistBuddy \
      -c "Set :CFBundleShortVersionString $disp_ver" \
      -c "Set :CFBundleVersion $BUILD_NUM" \
      -c "Set :GitCommit $GIT_COMMIT" \
      -c "Set :GitBranch $GIT_BRANCH" \
      -c "Set :BuildDate $BUILD_DATE" "$p"
  done

  # Sign (timed separately from compile).
  t2=$(date +%s)
  codesign --force --sign "$sign" ${hardsign[@]+"${hardsign[@]}"} "$OSAX/Contents/MacOS/ColumnTamer"
  codesign --force --sign "$sign" ${hardsign[@]+"${hardsign[@]}"} "$OSAX"
  codesign --force --sign "$sign" ${hardsign[@]+"${hardsign[@]}"} "$MENU/Contents/MacOS/ColumnTamerMenu"
  codesign --force --sign "$sign" ${hardsign[@]+"${hardsign[@]}"} "$MENU"
  t3=$(date +%s)

  echo "▸ Built in $((t1-t0))s, signed in $((t3-t2))s → $sign"
  echo "▸ osax: $OSAX"
  echo "▸ menu: $MENU"
}

# ── do_install_osax: admin popup (why + password) → cp to /Library ─────────
do_install_osax() {
  echo "▸ Dev-install osax (admin)"
  osascript <<ASCRIPT
set resp to display dialog "ColumnTamer dev run (make run) needs your admin password to install the just-built osax into the system path so Finder can load it for testing:

    /Library/ScriptingAdditions/ColumnTamer.osax

Finder only loads scripting additions from that path." default answer "" with title "ColumnTamer — Dev Install" buttons {"Cancel", "Install"} default button "Install" with hidden answer with icon caution
set thePass to text returned of resp
do shell script "rm -rf '$OSAX_SYS' && cp -R '$ROOT/build/ColumnTamer.osax' '$OSAX_SYS' && chown -R root:wheel '$OSAX_SYS'" password thePass with administrator privileges
ASCRIPT
}

# ── do_launch: kill menu, restart Finder, inject ───────────────────────────
do_launch() {
  echo "▸ Launch menu app"
  pkill -x ColumnTamerMenu 2>/dev/null || true
  for i in $(seq 1 25); do
    pgrep -x ColumnTamerMenu >/dev/null 2>&1 || break
    sleep 0.2
  done
  pkill -x ColumnTamerMenu 2>/dev/null || true
  sleep 0.3
  for i in 1 2 3; do
    if open "$ROOT/build/menubuild/ColumnTamerMenu.app" 2>/dev/null; then break; fi
    sleep 0.5
  done

  echo "▸ Restart Finder"
  killall Finder 2>/dev/null || true
  sleep 2

  echo "▸ Inject into Finder"
  osascript -e 'tell application "Finder" to «event CTmrIjct»' 2>&1 || \
    echo "  (inject failed — Finder may need restart: killall Finder)"
}

# ── do_sigcheck ────────────────────────────────────────────────────────────
do_sigcheck() {
  echo "▸ Signature check"
  codesign -dv "$OSAX" 2>&1 | grep -E "Identifier|Signature|TeamIdentifier"
  codesign -dv "$MENU" 2>&1 | grep -E "Identifier|Signature|TeamIdentifier"
}

# ── do_package: stage + pkgbuild + optional notarize ───────────────────────
do_package() {
  local stage="$ROOT/build/pkgroot"
  local scripts_dir="$ROOT/build/pkgscripts"
  local pkg="$ROOT/build/ColumnTamer-$VERSION.pkg"

  echo "▸ Stage payload"
  rm -rf "$stage" "$scripts_dir" "$pkg"
  mkdir -p "$stage/Applications" \
           "$stage/Library/ScriptingAdditions" \
           "$stage/Library/LaunchAgents" \
           "$scripts_dir"

  cp -R "$OSAX" "$stage/Library/ScriptingAdditions/ColumnTamer.osax"
  # Flatten menu .app to separate files — PackageKit relocates bundles with
  # matching CFBundleIdentifier. Flat files have no bundle ID → no relocation.
  # Postinstall assembles .app from these files and re-signs.
  mkdir -p "$stage/Applications/ColumnTamerMenu.app/Contents/MacOS"
  cp "$MENU/Contents/MacOS/ColumnTamerMenu" "$stage/Applications/ColumnTamerMenu.app/Contents/MacOS/ColumnTamerMenu"
  cp "$MENU/Contents/Info.plist" "$stage/Applications/ColumnTamerMenu.app/Contents/Info.plist"
  cp "$MENU/Contents/PkgInfo" "$stage/Applications/ColumnTamerMenu.app/Contents/PkgInfo" 2>/dev/null || true
  cp -R "$MENU/Contents/_CodeSignature" "$stage/Applications/ColumnTamerMenu.app/Contents/_CodeSignature" 2>/dev/null || true
  # Zap source bundle — no need keep after staging
  rm -rf "$OSAX" "$MENU"
  cp "$ROOT/columntamer.menu.plist" "$stage/Library/LaunchAgents/columntamer.menu.plist"

  # pkg-scripts: real committed files (source-controlled, reviewable).
  cp "$ROOT/scripts/pkg-scripts/preinstall"  "$scripts_dir/preinstall"
  cp "$ROOT/scripts/pkg-scripts/postinstall" "$scripts_dir/postinstall"
  chmod 755 "$scripts_dir/preinstall" "$scripts_dir/postinstall"

  # Optional notarize (pkg-level).
  local notarize=0
  if [[ -n "${DEVELOPER_IDENTITY:-}" && -n "${APPLE_ID:-}" \
     && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]]; then
    notarize=1
    echo "▸ Notarize: yes (Developer ID creds present)"
  else
    echo "▸ Notarize: skipped (some creds unset). pkg unsigned — Gatekeeper warns for others."
  fi

  echo "▸ pkgbuild (component)"
  # BundleIsRelocatable=false — PK relocate bug: bundle ID registered to
  # prior path (dev or pre-rehome install) = payload redirected away from
  # declared pkgroot. Force non-relocatable = PK honors stage paths.
  local complist="$ROOT/build/component.plist"
  printf '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0">\n<array>\n<dict>\n<key>RootRelativeBundlePath</key>\n<string>Applications/ColumnTamerMenu.app</string>\n<key>BundleIsRelocatable</key>\n<false/>\n</dict>\n</array>\n</plist>\n' > "$complist"
  local comp="$ROOT/build/ColumnTamer-component.pkg"
  pkgbuild \
    --root "$stage" \
    --component-plist "$complist" \
    --scripts "$scripts_dir" \
    --identifier "columntamer" \
    --version "$VERSION" \
    --ownership recommended \
    "$comp"

  # Zap staging dir AFTER pkg sealed.
  rm -rf "$stage"

  echo "▸ productbuild (wrap → rootVolumeOnly, no disk select)"
  # rootVolumeOnly deprecated but work — skip disk select on multi-volume Macs.
  local dist="$ROOT/build/Distribution.xml"
  cat >"$dist" <<XML
<?xml version="1.0" encoding="utf-8" standalone="no"?>
<installer-gui-script minSpecVersion="2">
  <title>ColumnTamer</title>
  <options customize="never" require-scripts="false" rootVolumeOnly="true"/>
  <choices-outline>
    <line choice="columntamer"/>
  </choices-outline>
  <choice id="columntamer" title="ColumnTamer">
    <pkg-ref id="columntamer"/>
  </choice>
  <pkg-ref id="columntamer" version="$VERSION" onConclusion="none">ColumnTamer-component.pkg</pkg-ref>
</installer-gui-script>
XML
  productbuild \
    --distribution "$dist" \
    --package-path "$ROOT/build" \
    "$pkg"
  rm -f "$comp"

  if [[ "$notarize" -eq 1 ]]; then
    echo "▸ Signing pkg with Developer ID Installer: ${DEVELOPER_IDENTITY_INSTALLER:-$DEVELOPER_IDENTITY}"
    productsign --sign "${DEVELOPER_IDENTITY_INSTALLER:-$DEVELOPER_IDENTITY}" "$pkg" "$pkg.signed"
    mv "$pkg.signed" "$pkg"
    echo "▸ Notarizing pkg…"
    xcrun notarytool submit "$pkg" \
      --apple-id "$APPLE_ID" \
      --team-id "$APPLE_TEAM_ID" \
      --password "$APPLE_APP_SPECIFIC_PASSWORD" \
      --wait
    echo "▸ Stapling ticket"
    xcrun stapler staple "$pkg"
  fi

  echo
  echo "══════════════════════════════════════════════════════════"
  echo " ✓ Packaged $VERSION"
  if [[ "$notarize" -eq 1 ]]; then
    echo "   Notarized + stapled"
  else
    echo "   Unsigned pkg (not notarized)"
  fi
  echo "   pkg: $pkg"
  echo "   install: sudo installer -pkg \"$pkg\" -target /"
  echo "══════════════════════════════════════════════════════════"
}

# ── Dispatch ───────────────────────────────────────────────────────────────
case "$MODE" in
  run)
    do_build Debug
    do_install_osax
    do_launch
    ;;
  build)
    do_build Debug
    ;;
  release)
    do_build Release
    do_sigcheck
    echo
    echo "══════════════════════════════════════════════════════════"
    echo " ✓ Release built"
    echo "   Run 'make package' for .pkg installer"
    echo "══════════════════════════════════════════════════════════"
    ;;
  package)
    do_build Release
    do_package
    ;;
  *)
    echo "✗ Unknown mode: $MODE (use run|build|release|package)"; exit 2
    ;;
esac
