// XPLock - lock Finder column view preview pane width.
// Injected into Finder via osax. Constructor swizzles NSBrowser width setters
// so the preview (last) column holds a fixed width instead of resizing chaos.
//
// Targets (AppKit, verified via lldb image lookup):
//   -[NSBrowser setWidth:ofColumn:]
//   -[NSBrowser _setWidth:ofColumn:stretchWindow:]
//   -[_NSBrowserPreviewColumnViewController widthThatFits]
// Detection: +[NSBrowser previewColumnViewControllerClass] + -[NSBrowser _columnControllerInColumn:]

#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>

static CGFloat  XPLLockedWidth = 320.0;
static BOOL     XPLEnabled     = NO;
static int      XPLGuard       = 0;   // reentrancy guard

// original IMPs
static void   (*orig_setWidth_ofColumn)(id, SEL, CGFloat, NSInteger)            = NULL;
static void   (*orig_setWidth_ofColumn_stretch)(id, SEL, CGFloat, NSInteger, BOOL) = NULL;
static CGFloat (*orig_widthThatFits)(id, SEL)                                   = NULL;

// private helpers (typed IMPs resolved at install)
//   -[NSBrowser _columnControllerInColumn:(NSInteger)]
static id (*xpl_columnControllerInColumn)(id, SEL, NSInteger) = NULL;

// ---- preview column detection ----------------------------------------------
static Class XPLPreviewClass(void) {
    Class pc = Nil;
    if ([NSBrowser respondsToSelector:@selector(previewColumnViewControllerClass)]) {
        pc = [NSBrowser performSelector:@selector(previewColumnViewControllerClass)];
    }
    return pc;
}

static BOOL XPLIsPreviewColumn(NSBrowser *browser, NSInteger col) {
    if (col < 0) return NO;
    Class pc = XPLPreviewClass();
    if (!pc) return NO;
    if (!xpl_columnControllerInColumn) return NO;
    @try {
        id ctrl = xpl_columnControllerInColumn(browser,
                                               @selector(_columnControllerInColumn:),
                                               col);
        return ctrl && [ctrl isKindOfClass:pc];
    } @catch (NSException *e) {
        NSLog(@"[XPLock] isPreviewColumn caught: %@", e);
        return NO;
    }
}

// ---- swizzled implementations ----------------------------------------------

// -[NSBrowser setWidth:ofColumn:]
static void xpl_setWidth_ofColumn(NSBrowser *self, SEL _cmd, CGFloat width, NSInteger col) {
    if (XPLEnabled && XPLGuard == 0 && XPLIsPreviewColumn(self, col)) {
        XPLGuard = 1;
        orig_setWidth_ofColumn(self, _cmd, XPLLockedWidth, col);
        XPLGuard = 0;
        return;
    }
    orig_setWidth_ofColumn(self, _cmd, width, col);
}

// -[NSBrowser _setWidth:ofColumn:stretchWindow:]
static void xpl_setWidth_ofColumn_stretch(NSBrowser *self, SEL _cmd,
                                          CGFloat width, NSInteger col, BOOL stretch) {
    if (XPLEnabled && XPLGuard == 0 && XPLIsPreviewColumn(self, col)) {
        width = XPLLockedWidth;   // force, let original do layout w/ fixed width
    }
    orig_setWidth_ofColumn_stretch(self, _cmd, width, col, stretch);
}

// -[_NSBrowserPreviewColumnViewController widthThatFits]
static CGFloat xpl_widthThatFits(id self, SEL _cmd) {
    if (XPLEnabled) return XPLLockedWidth;
    return orig_widthThatFits(self, _cmd);
}

// ---- swizzle helper ---------------------------------------------------------
static void XPLSwizzleInstance(Class cls, SEL sel, IMP newImp, void **origOut) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) {
        NSLog(@"[XPLock] WARN: method not found on %@: %@",
              NSStringFromClass(cls), NSStringFromSelector(sel));
        return;
    }
    if (origOut) *origOut = (void *)method_getImplementation(m);
    method_setImplementation(m, newImp);
    NSLog(@"[XPLock] swizzled -[%@ %@]", NSStringFromClass(cls), NSStringFromSelector(sel));
}

// ---- bootstrap --------------------------------------------------------------
static void XPLInstall(void) {
    if (XPLEnabled) return;

    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    CGFloat w = [ud floatForKey:@"XPLockPreviewWidth"];
    if (w >= 100.0 && w <= 2000.0) XPLLockedWidth = w;

    Class browserClass = [NSBrowser class];

    // resolve typed IMP for _columnControllerInColumn:
    Method cc = class_getInstanceMethod(browserClass,
                                        @selector(_columnControllerInColumn:));
    if (cc) {
        xpl_columnControllerInColumn = (id (*)(id, SEL, NSInteger))method_getImplementation(cc);
        NSLog(@"[XPLock] resolved _columnControllerInColumn:");
    } else {
        NSLog(@"[XPLock] WARN: _columnControllerInColumn: not found");
    }

    XPLSwizzleInstance(browserClass,
                       @selector(setWidth:ofColumn:),
                       (IMP)xpl_setWidth_ofColumn,
                       (void **)&orig_setWidth_ofColumn);
    XPLSwizzleInstance(browserClass,
                       @selector(_setWidth:ofColumn:stretchWindow:),
                       (IMP)xpl_setWidth_ofColumn_stretch,
                       (void **)&orig_setWidth_ofColumn_stretch);

    Class pc = XPLPreviewClass();
    if (pc) {
        XPLSwizzleInstance(pc,
                           @selector(widthThatFits),
                           (IMP)xpl_widthThatFits,
                           (void **)&orig_widthThatFits);
    } else {
        NSLog(@"[XPLock] WARN: no previewColumnViewControllerClass");
    }

    XPLEnabled = YES;
    NSLog(@"[XPLock] ENABLED, locked preview width = %.0f", XPLLockedWidth);
}

// osax event handler (declared in Info.plist OSAXHandlers). No-op; load is what matters.
OSStatus InjectHandler(const AppleEvent *ev, AppleEvent *reply, SRefCon refcon) {
    XPLInstall();
    return noErr;
}

// constructor: run as soon as dylib loads into a process.
__attribute__((constructor))
static void XPLCtor(void) {
    @autoreleasepool {
        NSString *bid = [[NSBundle mainBundle] bundleIdentifier];
        if (![bid isEqualToString:@"com.apple.finder"]) return;
        XPLInstall();
    }
}
