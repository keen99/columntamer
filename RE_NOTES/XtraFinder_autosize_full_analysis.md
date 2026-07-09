# XtraFinder Column Autosize — Full Static Analysis

Date: 2026-07-09

Binary analyzed:

```text
/Applications/XtraFinder.app/Contents/Resources/XtraFinderPlugins.bundle/Contents/MacOS/XtraFinderPlugins
```

Architecture used for addresses: `arm64e`.

Tools: `otool`, `nm`, `strings`, `lipo`, byte/disassembly inspection. Static analysis only.

## XFFitColumnWidthPlugin methods

```text
-[XFFitColumnWidthPlugin overrideMethods]                            0x4d87c
-[XFFitColumnWidthPlugin postLoad]                                   0x4d96c
-[XFFitColumnWidthPlugin userDefaultsChanged]                        0x4d9b4
+[XFFitColumnWidthPlugin listViewController:sizeToFitWidthOfColumn:]  0x4dcc8
+[XFFitColumnWidthPlugin fitListViewColumns:]                         0x4e378
+[XFFitColumnWidthPlugin fitListViewColumns:afterDelay:]              0x4e4c8
-[XFFitColumnWidthPlugin outlineView:sizeToFitWidthOfColumn:]         0x4e538
-[XFFitColumnWidthPlugin reloadData]                                 0x4e5cc
-[XFFitColumnWidthPlugin outlineViewItemDidExpand:]                   0x4e614
-[XFFitColumnWidthPlugin outlineViewItemDidCollapse:]                 0x4e65c
-[XFFitColumnWidthPlugin dataSourceItemsDidChange:]                   0x4e6a4
-[XFFitColumnWidthPlugin reloadDataForContainerNode:]                 0x4e6ec
+[XFFitColumnWidthPlugin fitColumnsOfColumnViewController:]           0x4e73c
+[XFFitColumnWidthPlugin fitColumns:]                                0x4e900
+[XFFitColumnWidthPlugin fitColumnsOfColumnView:]                     0x4ea2c
-[XFFitColumnWidthPlugin columnView:willStartUsingNode:forColumn:]     0x4ec5c
```

## Hook targets

`-[overrideMethods]` resolves these Finder-private classes:

```text
TListViewController
TColumnViewController
```

Version-gated hook map:

```objc
if (finderVersion <= 4) {
    hook TListViewController outlineView:sizeToFitWidthOfColumn:
    hook TListViewController reloadData
    hook TListViewController outlineViewItemDidCollapse:
    hook TListViewController outlineViewItemDidExpand:
} else {
    hook TListViewController dataSourceItemsDidChange:
}

if (finderVersion < 5) {
    hook TColumnViewController reloadDataForContainerNode:
} else {
    hook TColumnViewController columnView:willStartUsingNode:forColumn:
}
```

XtraFinder keeps originals under renamed selectors:

```text
XFFitColumnWidthPlugin_reloadData
XFFitColumnWidthPlugin_dataSourceItemsDidChange:
XFFitColumnWidthPlugin_outlineView:sizeToFitWidthOfColumn:
XFFitColumnWidthPlugin_outlineViewItemDidCollapse:
XFFitColumnWidthPlugin_outlineViewItemDidExpand:
XFFitColumnWidthPlugin_reloadDataForContainerNode:
XFFitColumnWidthPlugin_columnView:willStartUsingNode:forColumn:
```

## Trigger timing and debounce

Observed delay constants:

```text
0.30 seconds  0x8cb20
0.15 seconds  0x8dcf8
0.10 seconds  0x8c9d0
```

Behavior:

```objc
reloadData:
    call previous/original
    fitListViewColumns:self afterDelay:0.30

dataSourceItemsDidChange:
    call previous/original
    fitListViewColumns:self afterDelay:0.30

outlineViewItemDidExpand/Collapse:
    call previous/original
    fitListViewColumns:self afterDelay:0.15

reloadDataForContainerNode:
    call previous/original
    perform fitColumns:self afterDelay:0.10

columnView:willStartUsingNode:forColumn:
    call previous/original
    payload = @[ @(column), self ]
    perform fitColumnsOfColumnView:payload afterDelay:0.30
```

`fitListViewColumns:afterDelay:` cancels pending `fitListViewColumns:` calls for the same controller before scheduling another call. Debounce prevents repeated width writes during Finder data updates.

## Width algorithm

Core implementation: `+[XFFitColumnWidthPlugin listViewController:sizeToFitWidthOfColumn:]` at `0x4dcc8`.

Simplified pseudocode:

```objc
double sizeToFit(TListViewController *vc, NSInteger col) {
    if (col < 1) return 0;
    if (!featureEnabled) return 0;

    id view = [vc browserView];
    NSTableColumn *tc = [view tableColumns][col];
    if ([tc isHidden]) return 0;

    NSString *identifier = [tc identifier];
    if (![enabledByIdentifier[identifier] boolValue]) return 0;

    NSInteger rows = MIN([view numberOfRows], 100);
    double best = configuredMinWidth;

    for (NSInteger row = 0; row < rows; row++) {
        id item = [view itemAtRow:row];
        NSString *text = renderedDisplayText(view, tc, item);
        double width = measuredTextWidth(text);
        width += iconIndentTagAdjustments(view, tc, item);
        width += configuredPadding;
        best = MAX(best, width);
        if (best >= configuredMaxWidth) break;
    }

    return ceil(MIN(best, configuredMaxWidth));
}
```

Important details:

- Samples at most 100 rows.
- Skips hidden columns.
- Uses table-column identifier for per-type enablement.
- Extracts rendered text from `NSTextField` / `NSTableCellView` on modern Finder.
- Uses `viewForTableColumn:item:` on newer Finder.
- Older fallbacks include `dataCellForTableColumn:item:`, `objectValueForTableColumn:byItem:`, and formatter `stringForObjectValue:`.
- Name column receives icon, indentation, tag, and optional folder-count adjustments.
- Checks `_tagsImageView` using `object_getInstanceVariable` on newer view path.
- Sets column autoresizing style to zero before applying widths.
- Raises `maxWidth` when computed width exceeds current `maxWidth`, then calls `setWidth:`.
- Uses `ceil()` for final width.

## Preferences

```text
XtraFinder_XFFitColumnWidthPlugin_HasMinWidth
XtraFinder_XFFitColumnWidthPlugin_MinWidth
XtraFinder_XFFitColumnWidthPlugin_HasMaxWidth
XtraFinder_XFFitColumnWidthPlugin_MaxWidth
XtraFinder_XFFitColumnWidthPlugin_Padding
XtraFinder_XFFitColumnWidthPlugin_Name
XtraFinder_XFFitColumnWidthPlugin_Size
XtraFinder_XFFitColumnWidthPlugin_Date
XtraFinder_XFFitColumnWidthPlugin_Kind
XtraFinder_XFFitColumnWidthPlugin_Version
XtraFinder_XFFitColumnWidthPlugin_Comment
XtraFinder_XFFitColumnWidthPlugin_Label
```

Identifier mapping:

```text
name                                               -> Name
dateCreated/dateModified/dateLastOpened/dateAdded -> Date
size                                               -> Size
kind                                               -> Kind
version                                            -> Version
comment                                            -> Comment
label                                              -> Label
```

Min/max values are clamped to at least `100.0`. Missing max becomes `DBL_MAX`.

## Safe modern Finder strategy

Modern Finder hook points matching XtraFinder:

```text
TListViewController   dataSourceItemsDidChange:
TColumnViewController columnView:willStartUsingNode:forColumn:
```

Recommended ColumnTamer design:

1. Keep existing stable preview-clamp hooks unchanged.
2. Resolve Finder-private classes and selectors at runtime. Missing class/method means autosize disabled, not fatal.
3. Hook only modern Finder trigger selectors above.
4. Save current IMP as previous IMP and call it first. Do not assume current IMP is Apple's original because XtraFinder may already be loaded.
5. Debounce per controller for approximately 0.30 seconds.
6. Measure rendered cell text after Finder populates rows.
7. Sample at most 100 rows.
8. Apply min, max, and padding from ColumnTamer UI preferences.
9. Never swizzle broad `NSTableView` methods.
10. Never overwrite or call XtraFinder's renamed-original selectors.
11. Use a separate autosize reentrancy guard.
12. If XtraFinder fit-column feature is active, avoid dueling width writes: either skip ColumnTamer autosize or require explicit ownership policy.

## Coexistence hazards

- Multiple plugins may hook same Finder-private selector.
- Hook must chain to current IMP, not search for an assumed Apple IMP.
- Reinstalling same hook in one Finder process can make saved previous IMP point back to ColumnTamer.
- Broad `NSTableView` swizzles affect unrelated Finder views and collide with XtraFinder.
- Width writes during Finder reload/layout can recursively trigger layout.
- Debounce and post-update scheduling are required.
