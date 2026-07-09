# ColumnTamer Autosize — Safe Implementation Plan

## Preserve stable baseline

Do not modify existing preview-clamp behavior or swizzle helper semantics in `src/main.m`.

Existing stable hooks:

```text
NSBrowser setWidth:ofColumn:
NSBrowser _setWidth:ofColumn:stretchWindow:
_NSBrowserPreviewColumnViewController widthThatFits
```

Autosize must use separate state, guard, IMPs, and triggers.

## Modern Finder trigger hooks

Based on XtraFinder static analysis:

```text
TListViewController   dataSourceItemsDidChange:
TColumnViewController columnView:willStartUsingNode:forColumn:
```

Do not hook broad methods on `NSTableView`.

## Phase 1 — discovery only

At install:

1. Resolve both classes with `NSClassFromString`.
2. Resolve selectors with `class_getInstanceMethod`.
3. Verify method type encodings.
4. Log availability.
5. Install no autosize hooks yet.

Missing private class or selector disables corresponding autosize path.

## Phase 2 — preferences

Read disk-fresh values from `com.apple.finder`:

```text
ColumnTamerAutosizeEnabled
ColumnTamerAutosizeMin
ColumnTamerAutosizeMax
ColumnTamerAutosizePadding
```

Rules:

- UI values always win.
- Never write or overwrite preferences from osax.
- Validate finite numbers.
- Require min >= 0, max >= min, padding >= 0.
- Keep autosize guard separate from preview guard.

## Phase 3 — chain-safe hooks

For each hook:

1. Capture current IMP before replacement. Treat it as previous chain element, not necessarily Apple's original.
2. Call previous IMP first.
3. Schedule ColumnTamer work after Finder update completes.
4. Never install same hook twice in one Finder process.
5. Never call XtraFinder renamed-original selectors.

XtraFinder may already hook same selectors. Current IMP chaining preserves whichever plugin loaded first.

## Phase 4 — debounce

Debounce per controller/object:

```text
list data change: 0.30 seconds
column start-use: 0.30 seconds
```

Cancel pending work for same controller before scheduling replacement work.

Avoid immediate width writes inside Finder data/layout callbacks.

## Phase 5 — rendered content measurement

For each visible data column:

1. Skip hidden columns.
2. Sample at most 100 rows.
3. Prefer rendered `NSTextField` / `NSTableCellView` text.
4. Use `viewForTableColumn:item:` on modern Finder.
5. Fall back to object value / formatter only when rendered view unavailable.
6. Include icon, indentation, and tag allowance for name column.
7. Compute `ceil(maxMeasuredWidth + padding)`.
8. Clamp result to user min/max.
9. Set table column autoresizing style to none before width writes.
10. Increase table column `maxWidth` first if needed, then call `setWidth:`.

## XtraFinder coexistence policy

Detect `NSClassFromString(@"XFFitColumnWidthPlugin")`.

Preferred initial policy:

- If XtraFinder fit-column plugin is active, ColumnTamer autosize does not write widths.
- Preview clamp remains active.
- Menu/diagnostics report autosize suppressed by XtraFinder.

Later policy may allow explicit ColumnTamer ownership, but must avoid two delayed writers fighting over same columns.

## Testing gates

1. Stable baseline: preview clamp still works.
2. Discovery build: zero width changes, no crashes.
3. Passthrough hooks: previous IMP called exactly once.
4. Debounce test: repeated data changes produce one fit pass.
5. UI min/max test: values read without osax writes.
6. Long and short filenames: widths vary within min/max.
7. Empty folder: no width change or crash.
8. Finder relaunch: hooks install once.
9. XtraFinder loaded: suppression or safe chaining works.
10. Inspect crash reports after every injected test build.

## Release gate

Do not commit or release autosize until all tests above pass and Finder remains crash-free across repeated navigation and relaunch.
