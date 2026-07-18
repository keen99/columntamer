# ColumnTamer

Fix macOS Finder column-view column behavior. Currently: **locks the preview pane** to a fixed width, stopping erratic resize that pushes file columns off-screen. 11+ year Apple bug, unfixed through macOS Tahoe.

Planned: column width resizing (eventually replace XtraFinder's feature for users who don't need other XF features).

`XtraFinder` fixes file-column width but **skips preview pane by design**. ColumnTamer closes gap by swizzling AppKit's `NSBrowser` width setters.

## How it works

Injected into Finder as osax (Scripting Addition). Constructor swizzles:

- `-[NSBrowser setWidth:ofColumn:]`
- `-[NSBrowser _setWidth:ofColumn:stretchWindow:]`
- `-[NSBrowserPreviewColumnViewController widthThatFits]`

Preview column detected via `+[NSBrowser previewColumnViewControllerClass]` and `-[NSBrowser _columnControllerInColumn:]`

Live pref reload via distributed notification --- no Finder restart needed after changing width.

## Requirements

- macOS 10.15+ (built/tested on Sonoma 14.8, arm64 + arm64e)
- **SIP off** --- required for scripting addition loading into Finder.
  - **Disable SIP** (full off):
    1. Reboot into Recovery: Apple Silicon = hold power button until boot
       options; Intel = hold `Cmd+R` at boot.
    2. Terminal (Utilities menu): `csrutil disable`
    3. Reboot.
    Re-enable: same steps, `csrutil enable`.
  - **macOS 11 (Big Sur)+: Library Validation** --- Finder marked as platform
    binary since Big Sur. System rejects non-platform code (our osax) injected
    into Finder even with SIP fully off. Fix: disable Library Validation:
    ```bash
    sudo defaults write /Library/Preferences/com.apple.security.libraryvalidation.plist \
      DisableLibraryValidation -bool true
    killall Finder
    ```
    Re-enable: `-bool false`. Targeted (not full AMFI off). Verified working.
  - Apple Dev / Developer ID signed osax works with SIP off + LV disabled.
  - Apple will not notarize Finder osax injection (same as XtraFinder).
  - Target audience = existing XtraFinder users (already SIP off).


[![Latest release](https://img.shields.io/github/v/release/keen99/columntamer)](https://github.com/keen99/columntamer/releases/latest)

### Install from Release

Download the `.pkg` from the [latest release](https://github.com/keen99/columntamer/releases/latest).
The package is not notarized, so Gatekeeper will warn on first open.

**Option A --- Terminal (most reliable):**
```bash
sudo installer -pkg ColumnTamer-*.pkg -target /
```
This bypasses Gatekeeper entirely. You will be prompted for your password.

**Option B --- GUI with right-click open:**
1. Right-click `ColumnTamer-*.pkg` → Open
2. Click Install. If Gatekeeper still blocks, run:
   ```bash
   xattr -cr ColumnTamer-*.pkg
   ```
   Then double-click normally.

**Option C --- System Settings:**
If both above fail, go to System Settings → Privacy & Security and click "Open Anyway" next to the blocked package.

Restart Finder after installation if it did not restart automatically (the installer may prompt you). The osax loads when Finder launches.

Restart Finder:
  **Terminal:** `killall Finder`
  **GUI:** Hold Option/Alt or right-click Finder icon in Dock → Relaunch


## Build

Use `make` (thin router --- all logic in `scripts/`):

```bash
make build      # osax + menu app (Debug, signed)
make run        # build + inject into running Finder
make release    # Release build, signed artifacts
make package    # Release + .pkg installer (+notarize if DevID creds)
```

See `AGENTS.md` for full build/install/uninstall docs.

**Note on `make package` vs `make devinstall`:** PackageKit relocates `.app`
bundles when matching CFBundleIdentifier exists on disk (e.g., from a prior
build). `make package` deletes staging dir after building to prevent this.
`make devinstall` bypasses PackageKit entirely via direct file copy --- use
for day-to-day development.

## Install

```bash
make devinstall       # sudo dev install
# or via pkg:
sudo installer -pkg build/ColumnTamer-$VERSION.pkg -target /
```

Installs:
- osax → `/Library/ScriptingAdditions/ColumnTamer.osax`
- menu app → `/Applications/ColumnTamerMenu.app`
- LaunchAgent → `/Library/LaunchAgents/columntamer.menu.plist`

Menu app provides prefs panel + health indicator + Finder-reinject poll (osax reload on Finder restart).

## Uninstall

```bash
make uninstall
```

Removes everything (sweeps legacy `com.local.columntamer*` labels from pre-rename installs). Kills Finder at end to unload osax from RAM.

## Tune preview width

Via menu app Preferences or:

```bash
defaults write com.apple.finder ColumnTamerMinWidth -float 300
defaults write com.apple.finder ColumnTamerMaxWidth -float 500
# no Finder restart needed --- osax re-reads prefs live
```

Defaults: min=240, max=350 (300/400 after first run via CTmrReload).
Valid range: 240--6000.
Set both equal for fixed width. Set min > max to disable clamping (passthrough).

## Status

Stable preview-lock. Tested on 10.15 Catalina + Sonoma 14.8.


## License

MIT. See `LICENSE`.
