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
    NSLog(@"[ColumnTamer] reload: clamp [%.0f, %.0f]", CTmrMinWidth, CTmrMaxWidth);
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
    if (CTmrEnabled) {
        CGFloat w = orig_widthThatFits ? orig_widthThatFits(self, _cmd) : CTmrMinWidth;
        return CTmrClamp(w);
    }
    return orig_widthThatFits(self, _cmd);
}

// ---- swizzle helper ---------------------------------------------------------
static void CTmrSwizzleInstance(Class cls, SEL sel, IMP newImp, void **origOut) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) {
        NSLog(@"[ColumnTamer] WARN: method not found on %@: %@",
              NSStringFromClass(cls), NSStringFromSelector(sel));
        return;
    }
    if (origOut) *origOut = (void *)method_getImplementation(m);
    method_setImplementation(m, newImp);
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

    CTmrEnabled = YES;

    // listen for live pref changes from menu app (no Finder restart needed)
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDistributedCenter(), NULL, CTmrReloadCB,
        CFSTR("com.local.columntamer.prefsChanged"), NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately);

    NSLog(@"[ColumnTamer] ENABLED, preview width clamp [%.0f, %.0f]", CTmrMinWidth, CTmrMaxWidth);
}

// osax event handler (declared in Info.plist OSAXHandlers). No-op; load is what matters.
OSStatus InjectHandler(const AppleEvent *ev, AppleEvent *reply, SRefCon refcon) {
    CTmrInstall();
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
