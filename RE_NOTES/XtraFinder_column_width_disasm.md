# XtraFinder Column Width Plugin - Disassembly Analysis

## Binary: XtraFinderPlugins.bundle/Contents/MacOS/XtraFinderPlugins

### Class: XFFitColumnWidthPlugin

Hooks:
- `outlineView:sizeToFitWidthOfColumn:` (instance) → calls class method
- `listViewController:sizeToFitWidthOfColumn:` (class, real impl)
- `columnView:willStartUsingNode:forColumn:`
- `dataSourceItemsDidChange:`
- `outlineViewItemDidCollapse:` / `DidExpand:`
- `reloadData` / `reloadDataForContainerNode:`

UserDefaults keys: `XtraFinder_XFFitColumnWidthPlugin_*`
- HasMinWidth, HasMaxWidth, MinWidth, MaxWidth, Padding
- Per-column-type toggles: Name, Date, Size, Kind, Version, Label, Comment

### `+[listViewController:sizeToFitWidthOfColumn:]` at 0x4dcc8

Algorithm:
1. Guard: column < 1 → return 0
2. Guard: feature flag (w8 at x24) must be nonzero
3. Get tableColumn from listVC.browserView.tableColumns[columnIndex]
4. Check tableColumn.isHidden → skip
5. Check per-column-type enabled (identifier → user defaults dict → boolValue)
6. Cap rows to check at 100 (0x64)
7. Load padding from config (d0 at x8+0x668)
8. Check formatter responds
9. Check iconSize for non-text modes
10. Get font attributes
11. Column type 3 ↔ padding 42 or 12 default
12. Loop through rows measuring text width
13. Return max width + padding

## Find a next step: look at Preferences UI for settings integration
