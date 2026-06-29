# Agent Guidelines

## Build Commands

Use Makefile. **Do NOT call build.sh / build_pkg.sh directly** — Makefile routes
+ auto-signs. Make = thin router; logic in `scripts/*.sh` + `build.sh` +
`menu-app/build.sh`.

```bash
make build      # build osax + menu app (Debug), sign (Apple Dev by default,
                #   ad-hoc fallback). Does NOT inject.
make run        # build + dev inject (osascript event — needs osax installed
                #   in /Library/ScriptingAdditions first via `make install`)
make release    # RELEASE: smart-sign artifacts (osax + menu). No pkg.
make package    # PACKAGE: build + .pkg installer (+notarize if DevID creds)
make install    # sudo install to /Library/... (dev/testing). same layout as pkg
make uninstall  # sudo remove everything (osax + helper + menu + agents + prefs)
make clean      # wipe build/
make show-sign  # print detected signing identity + team
```

### run vs install

- `make run` only injects osax into running Finder. osax must already be
  installed in `/Library/ScriptingAdditions/`. First time: `make install`.
- `make install` = sudo copies to system paths + bootstraps LaunchAgents.
  Dev/testing path. Use `make package` + `installer` for clean pkg-based install.

## Project layout (system-type)

Different from mailframe/ocular (app-type). Columntamer injects into Finder:

- **osax** → `/Library/ScriptingAdditions/ColumnTamer.osax`
  (Finder loads scripting additions only from system path)
- **helper** → `/Library/Application Support/ColumnTamer/ColumnTamerHelper`
  (watches Finder PID, re-injects on Finder restart)
- **menu app** → `/Library/Application Support/ColumnTamer/ColumnTamerMenu.app`
  (LSUIElement menubar UI — prefs, diagnostics, enable toggle)
- **LaunchAgents** → `/Library/LaunchAgents/columntamer.{helper,menu}.plist`

**Not a portable .app.** System paths required (Finder osax search + root-owned
for persistence safety). Same constraint as XtraFinder.

- `VERSION` = single source of truth. Build number = `git rev-list --count HEAD`.
- Source `Info.plist`s never mutated — stamped copies in `build/` at release.
- New `.m`/`.swift`: picked up by build scripts (glob folder).

## Requirements

- macOS 10.15+
- **SIP off** + AMFI library validation disabled (required for Finder osax
  injection; Apple will not notarize injection. Same as XtraFinder.)
- arm64 + arm64e (Apple Silicon kernel flavors)

## uninstall details

`make uninstall` kills Finder at end (load-bearing — osax stays in Finder RAM
until restart). Script waits for Finder relaunch, warns if it didn't.

If you manually rm files without restart: osax still live. Always go through
`make uninstall`.

Sweeps legacy `com.local.columntamer*` labels (pre-rename installs).

---

## Conventions (keen99 mac tools)

Standard across mailframe / ocular / columntamer. Same rules apply to future tools.

- **Bundle ID**: bare-word, lowercase, product name. `mailframe`, `ocular`,
  `columntamer`. **Never** reverse-DNS (`com.x.y`, `io.keen99.y`). Sub-components:
  `<product>.<role>` (e.g. `columntamer.helper`). UserDefaults domain = bundle ID
  (read via `Bundle.main.bundleIdentifier`, no hardcoded literal).

- **macOS floor**: 10.15. Exception only if required API forces higher —
  document per-tool in TODO + AGENTS.md. All current tools (mailframe, ocular,
  columntamer) at 10.15.

- **Universal binary**: `x86_64` + `arm64` (+ `arm64e` for osax — Apple Silicon
  kernel requires matching slice). Intel + Apple Silicon both first-class.

- **Signing** — 3 flows, auto-pick best at build time:

  | Flow | When | Gatekeeper for others |
  |---|---|---|
  | Developer ID + notarize | `DEVELOPER_IDENTITY` + APPLE creds env set (paid) | passes |
  | Apple Development (free) | auto-detected from Keychain (dev default) | blocked, TCC stable on your Macs |
  | Ad-hoc `-` | no cert | blocked, TCC unstable |

  Dev builds (`make build`/`make run`) MUST prefer Apple Dev over ad-hoc when
  cert exists. Ad-hoc dev builds silently break TCC (notifications, screen-rec,
  keychain consent cached forever).

  **Dev signing uses `--timestamp=none`** (xcodebuild `OTHER_CODE_SIGN_FLAGS`,
  codesign without `--timestamp`) — skips Apple secure-timestamp server
  roundtrip (the slow part). TCC stability comes from cert identity
  (TeamIdentifier), not timestamp. Timestamp only matters post-cert-expiry
  (distribution concern) → release sets `SIGN_HARDEN=1` to re-enable.

  Release env vars (paid flow):
  ```bash
  export DEVELOPER_IDENTITY="Developer ID Application: Your Name (TEAMID)"
  export APPLE_ID="you@example.com"
  export APPLE_TEAM_ID="ABCDE12345"
  export APPLE_APP_SPECIFIC_PASSWORD="xxxx-xxxx-xxxx-xxxx"
  make release && make package
  ```

- **Make = thin router**. All build logic in `scripts/*.sh`. Rule: anything >3
  lines, or needs trap/loop/conditional → script, not Make recipe.

- **Verbs** (same names across repos): `run` (dev+launch), `build` (dev),
  `release` (signed artifacts), `package` (DMG/pkg + notarize), `clean`,
  `show-sign`, `install-tools`, `uninstall`.
  - `release` = sign runnable artifacts. Never notarizes, never packages. Fast.
  - `package` = distribute (app-type: DMG; system-type: .pkg) + notarize+staple.
    Requires `make release` first (app-type) or self-contained build (columntamer).

- **Login items / LaunchAgents**: never wrap binary in `/bin/sh` (shows as "sh"
  in System Settings → Login Items). `ProgramArguments[0]` = Mach-O / .app
  executable directly. `Label` = bare-word bundle ID. Menu/helper = real `.app`
  bundle with `CFBundleName` + `LSUIElement` so Sys Settings shows real name.

- **No lockfiles for single-instance**. Rely on launchd Label (one per Label by
  design). Rare dup launch path (manual `open`) not worth lockfile complexity
  + stale risk.

- **Legacy cleanup**: any tool shipped under old bundle ID/naming keeps
  uninstall path sweeping legacy labels + paths. (mailframe:
  `scripts/migrate-bundle-id.sh` / `cleanup-bundle-id.sh` for user state.)
