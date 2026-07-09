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
