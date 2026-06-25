# ColumnTamer TODO (from code review)

Testing required before each commit. Check box when verified.

## 🔴 HIGH — headline feature risk

- [ ] **H1: Stale NSUserDefaults cache**
  - `src/main.m` CTmrReload: add `CFPreferencesAppSynchronize(CFSTR("com.apple.finder"))` + `[ud synchronize]` before read
  - Test: change width in UI, Apply, verify Finder picks up immediately (no restart)

- [ ] **H2: Apply reports success with no proof osax loaded**
  - Add health indicator: osax acks injection via reverse distributed notification → menu shows "Active"
  - OR: Apply falls back to killall Finder if no ack within timeout
  - Make status label honest ("Applied — takes effect on next Finder launch" if not active)
  - Fix header comment `Main.swift:3` (still says killall Finder)

## 🟠 MEDIUM — correctness/stability

- [ ] **M1: Safe swizzle on inherited methods**
  - `src/main.m` CTmrSwizzleInstance: check if method owned by class; if inherited, `class_addMethod` override first
  - Prevents `widthThatFits` mutating superclass = visual breakage

- [ ] **M2: CTmrGuard stuck on throw**
  - `src/main.m:89-91`: wrap orig call in `@try/@finally`, reset guard in finally
  - Prevents clamp dying forever after one exception

- [ ] **M3: launchctl print-disabled parse fragile**
  - `menu-app/Main.swift` CTLogin: mirror state in own UserDefaults (`startAtLogin` bool) as source of truth
  - launchctl enable/disable only enacts, never reads

- [ ] **M4: Single-instance guard**
  - menu app: `applicationShouldHandleReopen` activate existing prefs, terminate late arrival
  - Named POSIXFileLock sentinel or distributed ping

- [ ] **M5: Apply upper bound 3000 not enforced**
  - `menu-app/Main.swift`: guard `mn <= 3000 && mx <= 3000`, clamp on controlTextDidChange
  - Wire up unused NSTextFieldDelegate conformance

## 🟠 MEDIUM — installer hygiene

- [ ] **M6: chown root:wheel on installed files**
  - `build_pkg.sh`: chown in staging (`sudo chown -R root:wheel "$STAGE"`) or postinstall

- [ ] **M7: Log dir 1777 symlink trap**
  - `build_pkg.sh`: chmod 755 not 1777; per-user logs under ~/Library/Logs/ColumnTamer/ via $HOME

- [ ] **M8: preinstall SystemUIServer activate may abort**
  - `build_pkg.sh`: drop `tell application "SystemUIServer" to activate` line

## 🟡 LOW — cleanup

- [ ] **L5: SF Symbol force-unwrap**
  - `menu-app/Main.swift:32`: `if let` with "CT" text fallback

- [ ] **L6: NSApp.activate deprecated**
  - `menu-app/Main.swift:156`: `NSApp.activate()` no-arg

- [ ] **L13: Helper logs inject FAILED forever, no backoff**
  - `ColumnTamerHelper`: exponential backoff or max-retry-then-quiet

- [ ] **L17: applyBtn keyEquivalent**
  - VERIFY: Enter should trigger Apply? Currently empty. Re-enable `"\r"` or leave off (was disabled to stop Enter firing Apply accidentally)

- [ ] **M10: README stale**
  - Wrong key (`ColumnTamerPreviewWidth`), wrong defaults (320/100-2000 vs 300,400/50-3000), wrong "killall Finder" claim

- [ ] **L4: CTmrClamp NaN guard**
  - `src/main.m`: `if (w != w) return CTmrMinWidth;`

- [ ] **L9: rebuildMenu rename or wire up**
  - rename to buildMenu, or rebuild on state change (osax active indicator)

- [ ] **L10: InjectHandler return real status**
  - `src/main.m`: populate reply with which methods swizzled, or document limitation

- [ ] **L11: /tmp/.columntamer.restart-finder predictable**
  - move to root-owned path or mktemp

## ✅ Verify not broken (skip unless regression)
- bundle-ID guard, @try/@catch, idempotent install, 3 swizzles, sdef codes
