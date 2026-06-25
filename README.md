# XPLock

Lock macOS Finder column-view **preview pane** to a fixed width. Stops the
erratic resize that pushes file columns off-screen. 11+ year old Apple bug,
unfixed through macOS Tahoe.

`XtraFinder` fixes file-column width but **skips the preview pane by design**.
XPLock closes that gap by swizzling AppKit's `NSBrowser` width setters.

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
./build.sh
```

Produces `build/XPLock.osax` (universal arm64 + arm64e, unsigned).

## Install

```bash
./install.sh
```

- Copies osax → `/Library/ScriptingAdditions/XPLock.osax`
- Installs watcher → `~/.local/bin/xplock-reinject`
- Installs LaunchAgent → `~/Library/LaunchAgents/com.local.xplock-reinject.plist`
- Re-injects into Finder automatically on Finder restart.

## Tune

```bash
defaults write com.apple.finder XPLockPreviewWidth -float 400
killall Finder
```

Default width: 320px.

## Files

- `src/main.m` — swizzle logic
- `build.sh` — compile + bundle
- `install.sh` — system install
- `xplock-reinject` — Finder PID watcher
- `com.local.xplock-reinject.plist` — LaunchAgent
- `test_inject.sh` — manual dlopen test via lldb

## Status

Prototype — working in initial testing. Not packaged for distribution yet.

## License

TBD (leaning MIT).
