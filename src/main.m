// ColumnTamer - clamp Finder column view preview pane width to min/max range.
// Injected into Finder via osax. Constructor swizzles NSBrowser width setters
// so the preview (last) column stays within [min, max] instead of resizing chaos.
//
// Targets (AppKit, verified via lldb image lookup):
//   -[NSBrowser setWidth:ofColumn:]
//   -[NSBrowser _setWidth:ofColumn:stretchWindow:]
//   -[_NSBrowserPreviewColumnViewController widthThatFits]
// Detection: +[NSBrowser previewColumnViewControllerClass] + -[NSBrowser _columnControllerInColumn:]
//
// Defaults (com.apple.finder domain):
//   ColumnTamerMinWidth  (CGFloat, default 240)
//   ColumnTamerMaxWidth  (CGFloat, default 350)
//   if min == max -> fixed width; if min > max -> disabled (passthrough)
//
// MINIMUM WIDTH LIMIT — practical floor is 240. Empirically tested:
//   below 240 Finder won't shrink the preview column further (241 works,
//   239 does not). Exact mechanism unknown — candidates are NSBrowser internal
//   validator, preview VC intrinsic content size, layout constraints. Not
//   worth chasing; 240 is usable.
//   We accept mn/mx >= 240 in code. Lower values rejected at UI.
//
// UPPER CAP 6000. Tested 6000 wide renders fine on this machine.
// Higher probably safe but unverified. Lower cap would block future
// ultra-wide/8K displays for no reason; keep headroom.

#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>

static CGFloat  CTmrMinWidth = 240.0;
static CGFloat  CTmrMaxWidth = 350.0;
static BOOL     CTmrEnabled     = NO;
static int      CTmrGuard       = 0;   // reentrancy guard
static int      CTmrSwizzledCount = 0;  // how many methods hooked (H2 health)

// Regular column autosize. Values come only from menu-app preferences.
static BOOL     CTmrAutosizeEnabled = YES;
static BOOL     CTmrXtraFinderAutosizeEnabled = NO;
static CGFloat  CTmrAutosizeMin = 120.0;
static CGFloat  CTmrAutosizeMax = 2000.0;
static CGFloat  CTmrAutosizePadding = 16.0;
static const void *CTmrAutosizeTokensKey = &CTmrAutosizeTokensKey;

static void CTmrReload(void) {
    // Force disk-fresh read: menu app writes from another process.
    // Without this, Finder's cached NSUserDefaults may be stale.
    CFPreferencesAppSynchronize(CFSTR("com.apple.finder"));
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud synchronize];
    // CFPreferencesCopyAppValue bypasses the in-process cache.
    CGFloat mn = 300.0, mx = 400.0;
    CFNumberRef mnRef = CFPreferencesCopyAppValue(CFSTR("ColumnTamerMinWidth"), CFSTR("com.apple.finder"));
    CFNumberRef mxRef = CFPreferencesCopyAppValue(CFSTR("ColumnTamerMaxWidth"), CFSTR("com.apple.finder"));
    if (mnRef) { CFNumberGetValue(mnRef, kCFNumberCGFloatType, &mn); CFRelease(mnRef); }
    if (mxRef) { CFNumberGetValue(mxRef, kCFNumberCGFloatType, &mx); CFRelease(mxRef); }
    if (mn >= 240.0 && mn <= 6000.0) CTmrMinWidth = mn;
    if (mx >= 240.0 && mx <= 6000.0) CTmrMaxWidth = mx;

    BOOL asEnabled = YES;
    CGFloat asMin = 120.0, asMax = 2000.0, asPadding = 16.0;
    CFPropertyListRef asEnabledRef = CFPreferencesCopyAppValue(CFSTR("ColumnTamerAutosizeEnabled"), CFSTR("com.apple.finder"));
    CFPropertyListRef xfEnabledRef = CFPreferencesCopyAppValue(CFSTR("XtraFinder_XFFitColumnWidthPlugin"), CFSTR("com.apple.finder"));
    CFPropertyListRef asMinRef = CFPreferencesCopyAppValue(CFSTR("ColumnTamerAutosizeMin"), CFSTR("com.apple.finder"));
    CFPropertyListRef asMaxRef = CFPreferencesCopyAppValue(CFSTR("ColumnTamerAutosizeMax"), CFSTR("com.apple.finder"));
    CFPropertyListRef asPaddingRef = CFPreferencesCopyAppValue(CFSTR("ColumnTamerAutosizePadding"), CFSTR("com.apple.finder"));
    if (asEnabledRef) {
        if (CFGetTypeID(asEnabledRef) == CFBooleanGetTypeID()) asEnabled = CFBooleanGetValue((CFBooleanRef)asEnabledRef);
        CFRelease(asEnabledRef);
    }
    CTmrXtraFinderAutosizeEnabled = NO;
    if (xfEnabledRef) {
        if (CFGetTypeID(xfEnabledRef) == CFBooleanGetTypeID()) {
            CTmrXtraFinderAutosizeEnabled = CFBooleanGetValue((CFBooleanRef)xfEnabledRef);
        } else if (CFGetTypeID(xfEnabledRef) == CFNumberGetTypeID()) {
            int enabledValue = 0;
            CFNumberGetValue((CFNumberRef)xfEnabledRef, kCFNumberIntType, &enabledValue);
            CTmrXtraFinderAutosizeEnabled = enabledValue != 0;
        }
        CFRelease(xfEnabledRef);
    }
    if (asMinRef) {
        if (CFGetTypeID(asMinRef) == CFNumberGetTypeID()) CFNumberGetValue((CFNumberRef)asMinRef, kCFNumberCGFloatType, &asMin);
        CFRelease(asMinRef);
    }
    if (asMaxRef) {
        if (CFGetTypeID(asMaxRef) == CFNumberGetTypeID()) CFNumberGetValue((CFNumberRef)asMaxRef, kCFNumberCGFloatType, &asMax);
        CFRelease(asMaxRef);
    }
    if (asPaddingRef) {
        if (CFGetTypeID(asPaddingRef) == CFNumberGetTypeID()) CFNumberGetValue((CFNumberRef)asPaddingRef, kCFNumberCGFloatType, &asPadding);
        CFRelease(asPaddingRef);
    }
    if (isfinite(asMin) && isfinite(asMax) &&
        asMin >= 0.0 && asMax >= asMin && asMax <= 6000.0) {
        CTmrAutosizeEnabled = asEnabled;
        CTmrAutosizeMin = asMin;
        CTmrAutosizeMax = asMax;
    }
    if (isfinite(asPadding)) {
        CTmrAutosizePadding = MAX(12.0, MIN(asPadding, 200.0));
    }
    NSLog(@"[ColumnTamer] reload: preview [%.0f, %.0f], autosize %@ [%.0f, %.0f] pad %.0f, XtraFinder fit %@",
          CTmrMinWidth, CTmrMaxWidth, CTmrAutosizeEnabled ? @"on" : @"off",
          CTmrAutosizeMin, CTmrAutosizeMax, CTmrAutosizePadding,
          CTmrXtraFinderAutosizeEnabled ? @"on" : @"off");
}

// distributed-notify callback (re-reads prefs live, no Finder restart)
static void CTmrReloadCB(CFNotificationCenterRef center,
                         void *observer, CFStringRef name,
                         const void *object, CFDictionaryRef info) {
    @autoreleasepool { CTmrReload(); }
}

// original IMPs
static void   (*orig_setWidth_ofColumn)(id, SEL, CGFloat, NSInteger)            = NULL;
static void   (*orig_setWidth_ofColumn_stretch)(id, SEL, CGFloat, NSInteger, BOOL) = NULL;
static CGFloat (*orig_widthThatFits)(id, SEL)                                   = NULL;
static void   (*prev_columnView_willStartUsingNode_forColumn)(id, SEL, id, const void *, NSInteger) = NULL;

// private helpers (typed IMPs resolved at install)
//   -[NSBrowser _columnControllerInColumn:(NSInteger)]
static id (*xpl_columnControllerInColumn)(id, SEL, NSInteger) = NULL;

// ---- preview column detection ----------------------------------------------
static Class CTmrPreviewClass(void) {
    Class pc = Nil;
    if ([NSBrowser respondsToSelector:@selector(previewColumnViewControllerClass)]) {
        pc = [NSBrowser performSelector:@selector(previewColumnViewControllerClass)];
    }
    return pc;
}

static BOOL CTmrIsPreviewColumn(NSBrowser *browser, NSInteger col) {
    if (col < 0) return NO;
    // M9 pre-filter: preview is always the LAST column. If col is not last,
    // skip the expensive private-API probe. numberOfColumns is private (no
    // header) -> resolve via runtime to avoid compile error. No cache (stale).
    unsigned int (*imp)(id,SEL) = (unsigned int(*)(id,SEL))
        [browser methodForSelector:@selector(numberOfColumns)];
    if (imp) {
        @try {
            unsigned int last = imp(browser, @selector(numberOfColumns));
            if (last > 0 && col != (NSInteger)last - 1) return NO;
        } @catch (NSException *e) {
            // transient; fall through to full probe
        }
    }
    Class pc = CTmrPreviewClass();
    if (!pc) return NO;
    if (!xpl_columnControllerInColumn) return NO;
    @try {
        id ctrl = xpl_columnControllerInColumn(browser,
                                               @selector(_columnControllerInColumn:),
                                               col);
        return ctrl && [ctrl isKindOfClass:pc];
    } @catch (NSException *e) {
        NSLog(@"[ColumnTamer] isPreviewColumn caught: %@", e);
        return NO;
    }
}

// clamp incoming width to [min,max]; if min>max return original (disabled).
// NOTE: below 240 Finder won't shrink further (mechanism unknown). See header.
static CGFloat CTmrClamp(CGFloat w) {
    // L4: guard NaN. NaN fails all comparisons -> would fall through to return w.
    if (w != w) return CTmrMinWidth;
    if (CTmrMinWidth > CTmrMaxWidth) return w;   // disabled
    if (w < CTmrMinWidth) return CTmrMinWidth;
    if (w > CTmrMaxWidth) return CTmrMaxWidth;
    return w;
}

// ---- swizzled implementations ----------------------------------------------

// -[NSBrowser setWidth:ofColumn:]
static void xpl_setWidth_ofColumn(NSBrowser *self, SEL _cmd, CGFloat width, NSInteger col) {
    if (CTmrEnabled && CTmrGuard == 0 && CTmrIsPreviewColumn(self, col)) {
        CGFloat cw = CTmrClamp(width);
        if (cw != width) {
            CTmrGuard = 1;
            @try {
                orig_setWidth_ofColumn(self, _cmd, cw, col);
            } @finally {
                CTmrGuard = 0;   // reset even if orig throws (else clamp dies forever)
            }
            return;
        }
    }
    orig_setWidth_ofColumn(self, _cmd, width, col);
}

// -[NSBrowser _setWidth:ofColumn:stretchWindow:]
static void xpl_setWidth_ofColumn_stretch(NSBrowser *self, SEL _cmd,
                                          CGFloat width, NSInteger col, BOOL stretch) {
    if (CTmrEnabled && CTmrGuard == 0 && CTmrIsPreviewColumn(self, col)) {
        width = CTmrClamp(width);
    }
    orig_setWidth_ofColumn_stretch(self, _cmd, width, col, stretch);
}

// -[_NSBrowserPreviewColumnViewController widthThatFits]
static CGFloat xpl_widthThatFits(id self, SEL _cmd) {
    if (CTmrEnabled && CTmrGuard == 0) {
        CGFloat w = orig_widthThatFits ? orig_widthThatFits(self, _cmd) : CTmrMinWidth;
        return CTmrClamp(w);
    }
    return orig_widthThatFits(self, _cmd);
}

// ---- regular column autosize ------------------------------------------------

static const char *CTmrUnqualifiedType(const char *type) {
    while (type && strchr("rnNoORV", *type)) type++;
    return type;
}

static BOOL CTmrTypeIsObject(const char *type) {
    type = CTmrUnqualifiedType(type);
    return type && (*type == '@' || *type == '#');
}

static BOOL CTmrTypeIsInteger(const char *type) {
    type = CTmrUnqualifiedType(type);
    return type && strchr("qQiIlLsScC", *type) != NULL;
}

static BOOL CTmrTypeIsPointer(const char *type) {
    type = CTmrUnqualifiedType(type);
    return type && *type == '^';
}

static BOOL CTmrMethodABI(id object, SEL selector, NSUInteger explicitArgs,
                          const char *returnType, const char **argumentTypes) {
    NSMethodSignature *signature = [object methodSignatureForSelector:selector];
    if (!signature || signature.numberOfArguments != explicitArgs + 2) return NO;
    const char *actualReturn = CTmrUnqualifiedType(signature.methodReturnType);
    if (returnType[0] == '@') {
        if (!CTmrTypeIsObject(actualReturn)) return NO;
    } else if (!actualReturn || actualReturn[0] != returnType[0]) {
        return NO;
    }
    for (NSUInteger index = 0; index < explicitArgs; index++) {
        const char *actual = CTmrUnqualifiedType([signature getArgumentTypeAtIndex:index + 2]);
        const char *expected = argumentTypes[index];
        if (expected[0] == '@') {
            if (!CTmrTypeIsObject(actual)) return NO;
        } else if (expected[0] == 'q') {
            if (!CTmrTypeIsInteger(actual)) return NO;
        } else if (!actual || actual[0] != expected[0]) {
            return NO;
        }
    }
    return YES;
}

static BOOL CTmrColumnStartHookABI(Method method) {
    if (!method || method_getNumberOfArguments(method) != 5) return NO;
    char *returnType = method_copyReturnType(method);
    char *columnViewType = method_copyArgumentType(method, 2);
    char *nodeType = method_copyArgumentType(method, 3);
    char *columnType = method_copyArgumentType(method, 4);
    BOOL valid = returnType && CTmrUnqualifiedType(returnType)[0] == 'v' &&
                 CTmrTypeIsObject(columnViewType) && CTmrTypeIsPointer(nodeType) &&
                 CTmrTypeIsInteger(columnType);
    free(returnType);
    free(columnViewType);
    free(nodeType);
    free(columnType);
    return valid;
}

static id CTmrCallId0(id object, SEL selector) {
    if (!object || !CTmrMethodABI(object, selector, 0, "@", NULL)) return nil;
    return ((id (*)(id, SEL))[object methodForSelector:selector])(object, selector);
}

static id CTmrCallId1Integer(id object, SEL selector, NSInteger value) {
    const char *args[] = { "q" };
    if (!object || !CTmrMethodABI(object, selector, 1, "@", args)) return nil;
    return ((id (*)(id, SEL, NSInteger))[object methodForSelector:selector])(object, selector, value);
}

static id CTmrCallId2Integers(id object, SEL selector, NSInteger first, NSInteger second) {
    const char *args[] = { "q", "q" };
    if (!object || !CTmrMethodABI(object, selector, 2, "@", args)) return nil;
    return ((id (*)(id, SEL, NSInteger, NSInteger))[object methodForSelector:selector])(object, selector, first, second);
}

static BOOL CTmrCallBool0(id object, SEL selector) {
    NSMethodSignature *signature = [object methodSignatureForSelector:selector];
    const char *resultType = signature ? CTmrUnqualifiedType(signature.methodReturnType) : NULL;
    if (!object || !signature || signature.numberOfArguments != 2 ||
        !resultType || !strchr("BcC", *resultType)) return NO;
    return ((BOOL (*)(id, SEL))[object methodForSelector:selector])(object, selector);
}

static BOOL CTmrCallBool2Integers(id object, SEL selector, NSInteger first, NSInteger second) {
    const char *args[] = { "q", "q" };
    NSMethodSignature *signature = [object methodSignatureForSelector:selector];
    const char *resultType = signature ? CTmrUnqualifiedType(signature.methodReturnType) : NULL;
    if (!object || !signature || signature.numberOfArguments != 4 ||
        !resultType || !strchr("BcC", *resultType) ||
        !CTmrTypeIsInteger([signature getArgumentTypeAtIndex:2]) ||
        !CTmrTypeIsInteger([signature getArgumentTypeAtIndex:3])) return NO;
    (void)args;
    return ((BOOL (*)(id, SEL, NSInteger, NSInteger))[object methodForSelector:selector])(object, selector, first, second);
}

static CGFloat CTmrCallCGFloat0(id object, SEL selector) {
    if (!object || !CTmrMethodABI(object, selector, 0, @encode(CGFloat), NULL)) return -1.0;
    return ((CGFloat (*)(id, SEL))[object methodForSelector:selector])(object, selector);
}

static void CTmrCallVoidCGFloat0(id object, SEL selector, CGFloat value) {
    const char *args[] = { @encode(CGFloat) };
    if (!object || !CTmrMethodABI(object, selector, 1, "v", args)) return;
    ((void (*)(id, SEL, CGFloat))[object methodForSelector:selector])(object, selector, value);
}

static CGFloat CTmrCallCGFloat1Integer(id object, SEL selector, NSInteger column) {
    const char *args[] = { "q" };
    if (!object || !CTmrMethodABI(object, selector, 1, @encode(CGFloat), args)) return -1.0;
    return ((CGFloat (*)(id, SEL, NSInteger))[object methodForSelector:selector])(object, selector, column);
}

static void CTmrCallVoidCGFloatInteger(id object, SEL selector, CGFloat width, NSInteger column) {
    const char *args[] = { @encode(CGFloat), "q" };
    if (!object || !CTmrMethodABI(object, selector, 2, "v", args)) return;
    ((void (*)(id, SEL, CGFloat, NSInteger))[object methodForSelector:selector])(object, selector, width, column);
}

static NSTextField *CTmrFindTextField(NSView *view, NSString *title) {
    if ([view isKindOfClass:[NSTextField class]]) {
        NSTextField *field = (NSTextField *)view;
        if ([field.stringValue isEqualToString:title]) return field;
    }
    for (NSView *subview in view.subviews) {
        NSTextField *field = CTmrFindTextField(subview, title);
        if (field) return field;
    }
    return nil;
}

static CGFloat CTmrRenderedCellChrome(NSTableView *tableView, id columnView,
                                      NSInteger browserColumn, NSFont *font,
                                      CGFloat browserGutter) {
    NSRange visibleRows = [tableView rowsInRect:tableView.visibleRect];
    if (visibleRows.location == NSNotFound || visibleRows.length == 0) return -1.0;
    NSDictionary *attributes = @{ NSFontAttributeName: font };
    NSUInteger end = MIN(NSMaxRange(visibleRows), (NSUInteger)tableView.numberOfRows);
    for (NSUInteger row = visibleRows.location; row < end; row++) {
        id item = CTmrCallId2Integers(columnView, @selector(itemAtRow:inColumn:), row, browserColumn);
        NSString *title = CTmrCallId0(item, @selector(previewItemTitle));
        if (![title isKindOfClass:[NSString class]] || title.length == 0) continue;
        CGFloat measuredText = [title sizeWithAttributes:attributes].width;
        for (NSInteger tableColumn = 0; tableColumn < tableView.numberOfColumns; tableColumn++) {
            NSView *cellView = [tableView viewAtColumn:tableColumn row:row makeIfNecessary:NO];
            NSTextField *field = cellView ? CTmrFindTextField(cellView, title) : nil;
            if (!field) continue;
            CGFloat textOrigin = [field convertPoint:NSZeroPoint toView:tableView].x;
            CGFloat internalWidth = MAX(0.0, field.fittingSize.width - measuredText);
            return MAX(0.0, textOrigin) + internalWidth + browserGutter;
        }
    }
    return -1.0;
}

static void CTmrFitColumn(id controller, NSInteger column) {
    if (!CTmrAutosizeEnabled || !controller || column < 0) return;

    @try {
        id columnView = CTmrCallId0(controller, @selector(columnView));
        if (!columnView) return;

        NSTableView *tableView = CTmrCallId1Integer(columnView, @selector(browserTableViewAtIndex:), column);
        if (![tableView isKindOfClass:[NSTableView class]] || tableView.numberOfRows <= 0) return;

        NSFont *font = nil;
        id prototype = CTmrCallId0(columnView, @selector(cellPrototype));
        if ([prototype respondsToSelector:@selector(font)]) font = CTmrCallId0(prototype, @selector(font));
        if (!font) font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
        NSDictionary *attributes = @{ NSFontAttributeName: font };

        // Match XtraFinder's modern column-view algorithm exactly: icon size +
        // 28 points of column chrome, plus 40 when color tags are visible.
        CGFloat iconWidth = CTmrCallCGFloat0(controller, @selector(calculateIconSize));
        if (iconWidth < 0.0) return;  // private ABI mismatch: fail closed
        CGFloat currentColumnWidth = CTmrCallCGFloat1Integer(columnView, @selector(widthOfColumn:), column);
        CGFloat browserGutter = currentColumnWidth - NSWidth(tableView.frame);
        if (!isfinite(browserGutter) || browserGutter < 0.0 || browserGutter > 100.0) browserGutter = 0.0;
        CGFloat renderedChrome = CTmrRenderedCellChrome(tableView, columnView, column, font, browserGutter);
        // Trailing-space preference is total fit safety margin. UI enforces
        // 12–200 points; old lower values are clamped during preference reload.
        CGFloat chromeWidth = renderedChrome >= 0.0
            ? renderedChrome + CTmrAutosizePadding
            : iconWidth + 28.0 + CTmrAutosizePadding + browserGutter;
        if (CTmrCallBool0(tableView, @selector(showingAnyColorTags))) chromeWidth += 40.0;

        CGFloat width = CTmrAutosizeMin;
        CGFloat widestTextWidth = 0.0;
        NSUInteger widestTitleLength = 0;
        NSInteger rows = tableView.numberOfRows;
        for (NSInteger row = 0; row < rows; row++) {
            if (CTmrCallBool2Integers(controller, @selector(isGroupRow:inColumn:), row, column)) continue;
            id item = CTmrCallId2Integers(columnView, @selector(itemAtRow:inColumn:), row, column);
            NSString *title = CTmrCallId0(item, @selector(previewItemTitle));
            if (![title isKindOfClass:[NSString class]] || title.length == 0) continue;
            CGFloat textWidth = [title sizeWithAttributes:attributes].width;
            CGFloat candidate = textWidth + chromeWidth;
            if (candidate > width) {
                width = candidate;
                widestTextWidth = textWidth;
                widestTitleLength = title.length;
            }
            if (width >= CTmrAutosizeMax) { width = CTmrAutosizeMax; break; }
        }

        width = ceil(MAX(CTmrAutosizeMin, MIN(width, CTmrAutosizeMax)));
        CTmrCallVoidCGFloatInteger(columnView, @selector(setWidth:ofColumn:), width, column);
        CGFloat applied = CTmrCallCGFloat1Integer(columnView, @selector(widthOfColumn:), column);
        NSLog(@"[ColumnTamer] autosize column %ld requested %.0f, applied %.0f, table %.0f, text %.0f, chrome %.0f, gutter %.0f, rendered %@, chars %lu (%ld rows)",
              (long)column, width, applied, NSWidth(tableView.frame), widestTextWidth,
              chromeWidth, browserGutter, renderedChrome >= 0.0 ? @"yes" : @"no",
              (unsigned long)widestTitleLength, (long)tableView.numberOfRows);
    } @catch (NSException *exception) {
        NSLog(@"[ColumnTamer] autosize column %ld failed: %@", (long)column, exception);
    }
}

// Modern Finder data callback. Call previous chain first, then debounce sizing.
static void xpl_columnView_willStartUsingNode_forColumn(id self, SEL _cmd,
                                                        id columnView, const void *node,
                                                        NSInteger column) {
    if (prev_columnView_willStartUsingNode_forColumn) {
        prev_columnView_willStartUsingNode_forColumn(self, _cmd, columnView, node, column);
    }
    if (!CTmrAutosizeEnabled || CTmrXtraFinderAutosizeEnabled || column < 0) return;

    NSNumber *columnKey = @(column);
    NSMutableDictionary *tokens = objc_getAssociatedObject(self, CTmrAutosizeTokensKey);
    if (!tokens) {
        tokens = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(self, CTmrAutosizeTokensKey, tokens, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    NSObject *token = [NSObject new];
    tokens[columnKey] = token;

    __weak id weakController = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        id controller = weakController;
        if (!controller) return;
        NSMutableDictionary *currentTokens = objc_getAssociatedObject(controller, CTmrAutosizeTokensKey);
        if (currentTokens[columnKey] != token) return;
        [currentTokens removeObjectForKey:columnKey];
        CTmrFitColumn(controller, column);
    });
}

// ---- swizzle helper ---------------------------------------------------------
static void CTmrSwizzleInstance(Class cls, SEL sel, IMP newImp, void **origOut) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) {
        NSLog(@"[ColumnTamer] WARN: method not found on %@: %@",
              NSStringFromClass(cls), NSStringFromSelector(sel));
        return;
    }
    // Safety: if sel is inherited (not owned by cls), class_getInstanceMethod
    // returns the SUPER's method and method_setImplementation would mutate it
    // globally, breaking unrelated subclasses. Detect inheritance: if cls's own
    // method table resolves to a different method pointer than super's, it's
    // owned. Otherwise add an override on cls first, then swap that local copy.
    Method superM = (class_getSuperclass(cls))
                    ? class_getInstanceMethod(class_getSuperclass(cls), sel)
                    : NULL;
    if (superM == m) {
        // inherited -> add override copy on cls so we don't touch super.
        if (!class_addMethod(cls, sel, newImp, method_getTypeEncoding(m))) {
            // lost a race or cls already overrides (shouldn't happen since
            // superM==m); fall through and set on the cls-owned method.
            m = class_getInstanceMethod(cls, sel);
        } else {
            // save orig IMP from super, method now owned by cls with newImp.
            if (origOut) *origOut = (void *)method_getImplementation(superM);
            CTmrSwizzledCount++;
            NSLog(@"[ColumnTamer] swizzled -[%@ %@] (added override, inherited from %@)",
                  NSStringFromClass(cls), NSStringFromSelector(sel),
                  NSStringFromClass(class_getSuperclass(cls)));
            return;
        }
    }
    if (origOut) *origOut = (void *)method_getImplementation(m);
    method_setImplementation(m, newImp);
    CTmrSwizzledCount++;
    NSLog(@"[ColumnTamer] swizzled -[%@ %@]", NSStringFromClass(cls), NSStringFromSelector(sel));
}

// ---- bootstrap --------------------------------------------------------------
static void CTmrInstall(void) {
    if (CTmrEnabled) return;

    CTmrReload();   // read prefs first time

    Class browserClass = [NSBrowser class];

    // resolve typed IMP for _columnControllerInColumn:
    Method cc = class_getInstanceMethod(browserClass,
                                        @selector(_columnControllerInColumn:));
    if (cc) {
        xpl_columnControllerInColumn = (id (*)(id, SEL, NSInteger))method_getImplementation(cc);
        NSLog(@"[ColumnTamer] resolved _columnControllerInColumn:");
    } else {
        NSLog(@"[ColumnTamer] WARN: _columnControllerInColumn: not found");
    }

    CTmrSwizzleInstance(browserClass,
                       @selector(setWidth:ofColumn:),
                       (IMP)xpl_setWidth_ofColumn,
                       (void **)&orig_setWidth_ofColumn);
    CTmrSwizzleInstance(browserClass,
                       @selector(_setWidth:ofColumn:stretchWindow:),
                       (IMP)xpl_setWidth_ofColumn_stretch,
                       (void **)&orig_setWidth_ofColumn_stretch);

    Class pc = CTmrPreviewClass();
    if (pc) {
        CTmrSwizzleInstance(pc,
                           @selector(widthThatFits),
                           (IMP)xpl_widthThatFits,
                           (void **)&orig_widthThatFits);
    } else {
        NSLog(@"[ColumnTamer] WARN: no previewColumnViewControllerClass");
    }

    Class columnVC = NSClassFromString(@"TColumnViewController");
    SEL columnStart = @selector(columnView:willStartUsingNode:forColumn:);
    Method columnStartMethod = columnVC ? class_getInstanceMethod(columnVC, columnStart) : NULL;
    if (CTmrColumnStartHookABI(columnStartMethod)) {
        CTmrSwizzleInstance(columnVC,
                           columnStart,
                           (IMP)xpl_columnView_willStartUsingNode_forColumn,
                           (void **)&prev_columnView_willStartUsingNode_forColumn);
    } else {
        NSLog(@"[ColumnTamer] WARN: modern column autosize hook unavailable: class=%@ method=%@ encoding=%s args=%u",
              columnVC ? NSStringFromClass(columnVC) : @"nil",
              columnStartMethod ? @"found" : @"missing",
              columnStartMethod ? method_getTypeEncoding(columnStartMethod) : "(null)",
              columnStartMethod ? method_getNumberOfArguments(columnStartMethod) : 0);
    }

    CTmrEnabled = YES;

    // listen for live pref changes from menu app (no Finder restart needed)
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDistributedCenter(), NULL, CTmrReloadCB,
        CFSTR("columntamer.prefsChanged"), NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately);

    NSLog(@"[ColumnTamer] ENABLED, preview width clamp [%.0f, %.0f] (%d swizzles)",
          CTmrMinWidth, CTmrMaxWidth, CTmrSwizzledCount);

    // H2: broadcast health to menu app. Payload = swizzle count (expected 3).
    // Menu app observes -> shows "Active". No ack = osax not loaded.
    NSDictionary *info = @{@"swizzles": @(CTmrSwizzledCount),
                           @"at": [NSDate date]};
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDistributedCenter(),
        CFSTR("columntamer.health"),
        NULL,
        (__bridge CFDictionaryRef)info,
        true);
}

// osax event handler (declared in Info.plist OSAXHandlers). No-op; load is what matters.
OSStatus InjectHandler(const AppleEvent *ev, AppleEvent *reply, SRefCon refcon) {
    CTmrInstall();
    // L10: report real status back to caller (helper). Text desc with
    // enabled/min/max so helper can log/branch on outcome.
    @try {
        NSDictionary *status = @{
            @"enabled": @(CTmrEnabled),
            @"min": @(CTmrMinWidth),
            @"max": @(CTmrMaxWidth),
        };
        if (reply) {
            NSData *bytes = [[status description] dataUsingEncoding:NSUTF8StringEncoding];
            AEDesc d = { typeNull, NULL };
            if (AECreateDesc(typeUTF8Text, bytes.bytes, bytes.length, &d) == noErr) {
                AEPutParamDesc(reply, keyDirectObject, &d);
                AEDisposeDesc(&d);
            }
        }
    } @catch (NSException *e) {
        NSLog(@"[ColumnTamer] InjectHandler reply build failed: %@", e);
    }
    return noErr;
}

// constructor: run as soon as dylib loads into a process.
__attribute__((constructor))
static void CTmrCtor(void) {
    @autoreleasepool {
        NSString *bid = [[NSBundle mainBundle] bundleIdentifier];
        if (![bid isEqualToString:@"com.apple.finder"]) return;
        CTmrInstall();
    }
}
