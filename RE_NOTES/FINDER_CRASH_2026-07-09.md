# Finder Crash Root Cause — 2026-07-09

## Symptom

Finder repeatedly crashed after experimental autosize hooks were deployed.

Crash reports:

```text
~/Library/Logs/DiagnosticReports/Finder-2026-07-09-*.ips
```

Exception:

```text
EXC_BAD_ACCESS / KERN_PROTECTION_FAILURE
fault address inside thread-0 stack guard
```

## Exact stack

Latest analyzed crash repeatedly contained:

```text
CTmrIsPreviewColumn
xpl_setWidth_ofColumn
xpl_setWidth_ofColumn
xpl_setWidth_ofColumn
...
```

This is stack overflow caused by direct recursion inside ColumnTamer.

## Root cause

Experimental rewrite broke `CTmrSwizzleInstance`.

For class-owned methods it performed replacement, then read current class IMP into `origOut`. Current IMP was already ColumnTamer replacement. Therefore:

```text
orig_setWidth_ofColumn == xpl_setWidth_ofColumn
```

Every call recursively called itself until stack exhaustion.

XtraFinder was loaded in same Finder process, but crash backtrace proves this specific crash came from ColumnTamer's broken IMP storage, not XtraFinder.

## Additional regression

Experimental rewrite removed exported `InjectHandler` expected by `Info.plist` `OSAXHandlers`. This caused:

```text
Finder got an error: Can’t continue «event CTmrIjct». (-1708)
```

## Resolution

`src/main.m` restored from stable branch HEAD. Stable implementation:

- Saves existing IMP before replacing it.
- Handles inherited methods by adding class-local override while preserving superclass IMP.
- Retains exported `InjectHandler`.
- Avoids reinstalling hooks when already enabled.

Stable baseline rebuilt and deployed using `make run`. Finder remained alive and injection returned enabled status.

## Rule for future autosize work

- Never rewrite stable preview-clamp swizzle infrastructure.
- Add autosize as isolated hooks.
- Save current IMP as previous before replacement.
- Never re-swizzle same selector within one Finder process.
- Never broadly swizzle `NSTableView` reload/row methods.
- Inspect crash report before proposing recursion or compatibility theories.
