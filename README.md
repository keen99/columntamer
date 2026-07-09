# ColumnTamer

Fix macOS Finder column-view column behavior. Currently: **locks the preview pane** to a fixed width, stopping erratic resize that pushes file columns off-screen. 11+ year Apple bug, unfixed through macOS Tahoe.

Planned: column width resizing (eventually replace XtraFinder's feature for users who don't need other XF features).

`XtraFinder` fixes file-column width but **skips preview pane by design**. ColumnTamer closes gap by swizzling AppKit's `NSBrowser` width setters.

## How it works

Injected into Finder as osax (Scripting Addition). Constructor swizzles:

- `-[NSBrowser setWidth:ofColumn:]`
- `-[NSBrowser _setWidth:ofColumn:stretchWindow:]`
- `-[NSBrowserPreviewColumnViewController widthThatFits]`

Preview column detected via `+[NSBrowser previewColumnViewControllerClass]`
+ `-[NSBrowser _columnControllerInColumn:]`

Live pref reload via distributed notification --- no Finder restart needed after changing width.

## Requirements

- macOS 10.15+ (built/tested on Sonoma 14.8, arm64 + arm64e)
- **SIP off** --- required for unsigned scripting addition loading into Finder.
  - Apple Dev / Developer ID signed osax works with SIP off alone.
  - Ad-hoc/unsigned builds may need `amfi_get_out_of_my_way=1` boot-arg additionally.
  - Apple will not notarize Finder osax injection.
  - Target audience = existing XtraFinder users (already SIP off).

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
- helper → `/Library/Application Support/ColumnTamer/ColumnTamerHelper`
- menu app → `/Library/Application Support/ColumnTamer/ColumnTamerMenu.app`
- LaunchAgents → `/Library/LaunchAgents/columntamer.{helper,menu}.plist`

Helper watches Finder PID, auto-injects. Menu app provides prefs panel + health indicator.

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

Stable preview-lock. Tested on 10.15 Catalina + Sonoma 14.8. Not packaged for public distribution yet.

## License

MIT. See `LICENSE`.
