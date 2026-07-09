# Reverse-Engineering Notes

## Files

- `XtraFinder_autosize_full_analysis.md` — detailed XFFitColumnWidthPlugin hook map, addresses, timing, algorithm, preferences, coexistence strategy.
- `XtraFinder_column_width_disasm.md` — original short disassembly summary.
- `listView_sizeToFit_disasm.txt` — raw disassembly excerpt for list-view width calculation.
- `AUTOSIZE_IMPLEMENTATION_PLAN.md` — safe ColumnTamer implementation plan based on modern Finder hooks.
- `FINDER_CRASH_2026-07-09.md` — crash-report root cause and rollback details.

## Binary analyzed

```text
/Applications/XtraFinder.app/Contents/Resources/XtraFinderPlugins.bundle/Contents/MacOS/XtraFinderPlugins
```

Results are static reverse engineering. Runtime selectors remain private API and require defensive resolution.
