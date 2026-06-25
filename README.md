# ColumnTamer

Fix macOS Finder column-view column behavior. Currently: **locks the preview pane** to a fixed width, stopping the erratic resize that pushes file columns off-screen. 11+ year Apple bug, unfixed through macOS Tahoe.

Planned: column width resizing (eventually replace XtraFinder's feature for users who don't need other XF features).

`XtraFinder` fixes file-column width but **skips the preview pane by design**. ColumnTamer closes that gap by swizzling AppKit's `NSBrowser` width setters.

## How it works

Injected into Finder as an osax (Scripting Addition). Constructor swizzles:

- `-[NSBrowser setWidth:ofColumn:]`
- `-[NSBrowser _setWidth:ofColumn:stretchWindow:]`
- `-[NSBrowserPreviewColumnViewController widthThatFits]`

Preview column detected via `+[NSBrowser previewColumnViewControllerClass]`
+ `-[NSBrowser _columnControllerInColumn:]` — no XtraFinder dependency.

## Requirements

- macOS 11.0+ (built/tested on Sonoma 14.8, arm64 + arm64e)
- **SIP off** + AMFI library validation disabled
  - Same requirement as XtraFinder. AMFI blocks unsigned dylib load into Apple
    processes when SIP is on. Apple will not notarize Finder osax injection.
  - Target audience = existing XtraFinder users (already SIP off).

## Build

```bash
./build.sh        # osax only
./build_pkg.sh    # osax + .pkg installer
```

Produces `build/ColumnTamer.osax` and `build/ColumnTamer-0.1.0.pkg`
(universal arm64 + arm64e, ad-hoc signed).

## Install

```bash
sudo installer -pkg build/ColumnTamer-0.1.0.pkg -target /
```

Installs:
- osax → `/Library/ScriptingAdditions/ColumnTamer.osax`
- helper → `/Library/Application Support/ColumnTamer/ColumnTamerHelper`
- LaunchAgent → `/Library/LaunchAgents/com.local.columntamer.helper.plist`

Helper watches Finder PID, auto-injects on Finder restart.

## Uninstall

```bash
./uninstall.sh
```

Removes everything (also cleans legacy `XPLock` artifacts from prior versions).

## Tune preview width

```bash
defaults write com.apple.finder ColumnTamerPreviewWidth -float 400
killall Finder
```

Default width: 320px. Valid range: 100–2000px.

## Files

- `src/main.m` — swizzle logic
- `build.sh` — compile + bundle osax
- `build_pkg.sh` — build + .pkg installer
- `install.sh` — local dev install (no pkg)
- `uninstall.sh` — remove all (incl legacy)
- `ColumnTamerHelper` — Finder PID watcher
- `com.local.columntamer.helper.plist` — LaunchAgent
- `test_inject.sh` — manual dlopen test via lldb

## Status

Prototype — preview-lock working. Not packaged for public distribution yet.

## License

MIT.
