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
    // Broadcast health on inject too — menu launched after osax load misses
    // ctor broadcast. Helper poll fires inject periodically = menu gets ack.
    @try {
        NSDictionary *hinfo = @{@"swizzles": @(CTmrSwizzledCount),
                               @"at": [NSDate date]};
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDistributedCenter(),
            CFSTR("columntamer.health"),
            NULL,
            (__bridge CFDictionaryRef)hinfo,
            true);
    } @catch (NSException *e) {
        NSLog(@"[ColumnTamer] InjectHandler health broadcast failed: %@", e);
    }
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
