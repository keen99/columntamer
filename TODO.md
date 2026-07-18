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

## 🔴 HIGH — reengineer ColumnTamerHelper (current shell-script solution unacceptable)

- [ ] **Replace shell helper with compiled Swift .app bundle**
  - Current: zsh script `while true` polling pgrep every 5s. Multiple bugs:
    1. `open` on shell script = Terminal.app spawns visible window (hit 2026-07-17)
    2. Hardcoded `/usr/bin/launchctl` broke on macOS 15 (moved to `/bin`)
    3. Poll loop = CPU ticks forever, 5s Finder-restart latency
    4. No signal handling, no clean shutdown
    5. Plain exec not .app = System Settings shows wrong name
       (violates AGENTS.md: "Menu/helper = real .app bundle with CFBundleName + LSUIElement")
    6. Reinject spam on Finder PID flicker (crash loops = inject thrash)
    7. No entitlement-clean TCC (shell = ambient user perms)
  - Target: Swift (or ObjC) menubar-style .app
    - CFBundleName="ColumnTamerHelper", LSUIElement=true (no Dock icon)
    - Bundle ID: `columntamer.helper`
    - Sign same as menu app (Apple Dev dev / Developer ID release)
  - Core mechanism — event-driven NOT poll:
    - A. `NSWorkspaceDidLaunchApplicationNotification` /
      `NSWorkspaceDidTerminateApplicationNotification` for Finder
      (`NSWorkspace.shared.notificationCenter`). Instant, zero CPU. PREFERRED.
    - B. fallback: `dispatch_source_t` on Finder task port (overkill)
  - On Finder (re)launch:
    - Brief settle wait via NSTimer 1-2s (not sleep)
    - Inject via `NSAppleEventDescriptor` (not shell osascript)
    - Backoff on fail (keep MAX_FAILS=6 logic, port to Swift)
    - Log to `os_log` unified logging (not ~/Library/Logs flat file)
  - Packaging:
    - Helper .app staged like menu .app in pkgroot
    - LaunchAgent `ProgramArguments[0]` = helper .app executable direct (Mach-O)
      per AGENTS.md "never wrap in /bin/sh" — Sys Settings shows real name
    - postinstall: NEVER `open` helper. LaunchAgent owns lifecycle
      (enable+kickstart if 15 auto-disabled, else RunAtLoad at login)
  - Lifecycle:
    - launchd KeepAlive=true relaunch on crash
    - SIGTERM handler: cancel observers, exit 0
    - No lockfile (AGENTS.md: launchd Label singleton)
  - Signing/arch:
    - Universal: x86_64 + arm64 + arm64e (match osax + menu)
    - `-target ...-apple-macosx10.15` (keep floor)
    - Arch guard in build script (catch regress like menu-app had)
  - Acceptance:
    - No Terminal window on install ever
    - No hardcoded `/usr/bin` paths (bare cmds / Bundle paths)
    - Finder restart detected <1s
    - Sys Settings → Login Items shows "ColumnTamerHelper" not "sh"
    - Clean uninstall (kill + rm + Finder restart, osax flushed from RAM)
    - Works 10.15 / 14 / 15 (Intel + Apple Silicon)
  - Files:
    - New: `helper-src/Main.swift`, `helper-src/Info.plist`, `helper-app/build.sh`
    - Delete: `ColumnTamerHelper` (shell script)
    - Update: `scripts/build.sh` (build helper .app alongside menu .app)
    - Update: `scripts/pkg-scripts/postinstall` (drop helper spawn, LaunchAgent only)
    - Update: `scripts/devinstall.sh`, `scripts/uninstall.sh` (new paths)
    - Update: `AGENTS.md` (helper now .app, drop shell-script mention)

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
