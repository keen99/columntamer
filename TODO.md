# ColumnTamer TODO (from code review)

Testing required before each commit. Check box when verified.

All HIGH/MEDIUM items resolved. LOW cleanup items tracked below.

## 🟡 LOW — cleanup (verified done)

- [x] **L4: CTmrClamp NaN guard**
  - `src/main.m`: `if (w != w) return CTmrMinWidth;` — done

- [x] **L5: SF Symbol force-unwrap**
  - `menu-app/Main.swift:32`: code now draws icon with manual `NSBezierPath` — no SF Symbols used, no force-unwrap

- [x] **L6: NSApp.activate deprecated**
  - `menu-app/Main.swift:156`: uses `NSApp.activate(ignoringOtherApps: true)` — not the deprecated no-arg variant

- [x] **L9: rebuildMenu rename or wire up**
  - Named `buildMenu()`, called from health notification callback and `applicationDidFinishLaunching` — wired up

- [x] **L10: InjectHandler return real status**
  - `src/main.m`: populates reply with `@{@"enabled": @(CTmrEnabled), @"min": @(...), @"max": @(...)}` — done

- [x] **L11: /tmp/.columntamer.restart-finder predictable**
  - pkg scripts use `/var/run/.columntamer.restart` (root-owned path, not /tmp) — resolved

- [x] **L13: Helper logs inject FAILED forever, no backoff**
  - `ColumnTamerHelper`: exponential backoff implemented (`MAX_FAILS=6`, `backoff *= 2` capped at 60s)

- [x] **L17: applyBtn keyEquivalent**
  - Deliberately stripped (`keyEquivalent = ""`). Enter disabled to prevent accidental Apply from keyboard while typing in fields. If user wants Enter-to-apply later, re-enable `"\r"` in `PrefsController.build()`.

- [x] **M5: Apply upper bound 3000 not enforced (duplicate/stale)**
  - Code intentionally uses 6000 cap per `main.m`: "UPPER CAP 6000. Tested 6000 wide renders fine on this machine. Lower cap would block future ultra-wide/8K displays." Menu guards `mx <= 6000`. 3000 bound was old draft limit — removed.

- [x] **M10: README stale**
  - Fixed 2026-07-09. Wrong keys (`ColumnTamerPreviewWidth` → `ColumnTamerMinWidth`/`ColumnTamerMaxWidth`), wrong defaults, wrong paths, stale `killall Finder` claim — all corrected.

- [x] **Strip keyboard shortcuts from menu items**
  - Done. No `keyEquivalent` on Preferences or Diagnostics menu items. Quit retains `q` (standard, works in LSUIElement app).

## ✅ Verify not broken (skip unless regression)
- bundle-ID guard, @try/@catch, idempotent install, 3 swizzles, sdef codes

## 🔴 HIGH — reengineer helper/menu/app architecture

Reference: XtraFinder dmg (`/Volumes/XtraFinder/`, Instruction.rtf, 2026-07-18).
XF layout = `XtraFinder.app` + `XtraFinderInjector.osax` + `ScriptingAdditions/`
symlink + `Instruction.rtf`. Drag install (no pkg). User copies:
- `.app` → `/Applications`
- `.osax` → `/Library/ScriptingAdditions`
No helper process at all. Update = copy `.app` only. Uninstall = rm both +
`defaults delete DisableLibraryValidation`.

XF Instruction.rtf confirms our findings:
- SIP off required (macOS 11+)
- `sudo defaults write /Library/Preferences/com.apple.security.libraryvalidation.plist
  DisableLibraryValidation -bool true` (Library Validation gate — our root cause
  for osax load fail, AMFI kernel log proven 2026-07-18)
- `sudo nvram boot-args=-arm64e_preview_abi` (Apple Silicon, third-party arm64e
  load — we may need this for osax arm64e slice on ASi)

- [ ] **Move menu `.app` to `/Applications`** (match XF + user-friendly relaunch)
  - Current `/Library/Application Support/ColumnTamer/` = not Spotlight-findable,
    not drag-launch, unfamiliar. AGENTS.md system-path layout was inherited
    assumption, not requirement. XF = /Applications standard.
  - Osax stays `/Library/ScriptingAdditions/` (Finder load path, required).
  - Split locations = unavoidable (osax must be system path). Fine.
  - No symlinks/aliases (unreliable on macOS, drift over time).
  - Update build.sh pkgroot stage: `Applications/ColumnTamerMenu.app` +
    `Library/ScriptingAdditions/ColumnTamer.osax`.
  - Update LaunchAgent `ProgramArguments[0]` path → `/Applications/...`.
  - Update devinstall.sh, uninstall.sh paths.

- [ ] **Fold reinject logic into menu app, drop helper**
  - Verified 2026-07-18: with Library Validation disabled, Finder auto-loads
    osax on (re)launch. Helper reinject redundant for normal Finder restart.
    (zinc test: killall Finder → osax reloaded in new Finder PID.)
  - Helper still useful edge case: Finder crash mid-session where osax drops.
    XF exhibits this too. But shell-script poll = expensive (5s loop + osascript
    exec per cycle). Menu already runs NSApp event loop = free observer.
  - Menu add `NSWorkspace.shared.notificationCenter` observer for
    `NSWorkspaceDidLaunchApplicationNotification` / `DidTerminate` filtered to
    Finder. Event-driven, zero CPU, instant. ~3 lines.
  - On Finder (re)launch: NSTimer settle 1-2s, inject via NSAppleEventDescriptor
    (not osascript shell), backoff on fail (port MAX_FAILS=6 logic).
  - Delete `ColumnTamerHelper` shell script + `columntamer.helper` LaunchAgent.
  - One LaunchAgent (`columntamer.menu`) owns everything. Simpler.
  - Cuts: shell spawn bug, Terminal window bug, launchctl bootstrap dance,
    dup-helper on reinstall, System Settings "David Raistrick" leak (helper
    had no CFBundleName → cert name).

- [ ] **Menu LaunchAgent policy: RunAtLoad=true, KeepAlive=false**
  - Menu = UI only (prefs, status, diag). Osax in Finder does real work.
    Menu dead does not stop CT functioning.
  - Crash low-risk (Swift, simple UI). No auto-respawn needed.
  - KeepAlive=true = user Quit respawns immediately (bad UX).
  - RunAtLoad=true: launch at login. User Quit = stays quit until relogin or
    manual relaunch (now easy via /Applications).
  - Helper (if kept separate): KeepAlive=true. Must run. But if folded into
    menu, only menu's RunAtLoad matters.

- [ ] **If keeping helper (fallback if fold rejected)**
  - Compile to Swift .app (CFBundleName="ColumnTamerHelper", LSUIElement=true,
    bundle id `columntamer.helper`), sign same as menu.
  - Event-driven not poll (NSWorkspace observer, not `while true` + pgrep).
  - Log to `os_log` not flat file.
  - SIGTERM handler, launchd KeepAlive=true.
  - Universal x86_64 + arm64 + arm64e, -target macosx10.15, arch guard.

- [ ] **Acceptance (architecture work overall)**
  - `.app` in `/Applications`, launchable by user
  - No Terminal window on install ever
  - No hardcoded `/usr/bin` paths
  - No helper dup-spawn, no shell-script poll
  - System Settings → Login Items shows "ColumnTamerMenu" not "sh" or cert name
  - Menu dead = CT still clamps columns (osax independent)
  - Works 10.15 / 14 / 15 (Intel + Apple Silicon)

## 🔬 Future investigation

- [ ] **Investigate breaking the ~240 preview-pane min-width floor**
  - Empirically Finder won't shrink preview column below 240 (241 ok, 239 not)
  - Mechanism unknown. Candidates to probe:
    - `-[NSBrowser _validateNewWidthOfColumn:width:]` (swizzle? hard-floor 100 observed but real wall higher)
    - `-[NSBrowser minColumnWidth]` / ivar `_minColumnWidth`
    - preview VC intrinsic content size / `widthThatFits` floor inside AppKit
    - Auto-layout constraints on preview VC view hierarchy
    - `_calculateSizeToFitWidthOfColumn:testLoadedOnly:`
  - If swizzling the validator lifts it, drop UI floor below 240
  - Low priority: 240 usable for preview pane
