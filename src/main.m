// CTmrock - lock Finder column view preview pane width.
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

static CGFloat  CTmrLockedWidth = 320.0;
static BOOL     CTmrEnabled     = NO;
static int      CTmrGuard       = 0;   // reentrancy guard

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

// ---- swizzled implementations ----------------------------------------------

// -[NSBrowser setWidth:ofColumn:]
static void xpl_setWidth_ofColumn(NSBrowser *self, SEL _cmd, CGFloat width, NSInteger col) {
    if (CTmrEnabled && CTmrGuard == 0 && CTmrIsPreviewColumn(self, col)) {
        CTmrGuard = 1;
        orig_setWidth_ofColumn(self, _cmd, CTmrLockedWidth, col);
        CTmrGuard = 0;
        return;
    }
    orig_setWidth_ofColumn(self, _cmd, width, col);
}

// -[NSBrowser _setWidth:ofColumn:stretchWindow:]
static void xpl_setWidth_ofColumn_stretch(NSBrowser *self, SEL _cmd,
                                          CGFloat width, NSInteger col, BOOL stretch) {
    if (CTmrEnabled && CTmrGuard == 0 && CTmrIsPreviewColumn(self, col)) {
        width = CTmrLockedWidth;   // force, let original do layout w/ fixed width
    }
    orig_setWidth_ofColumn_stretch(self, _cmd, width, col, stretch);
}

// -[_NSBrowserPreviewColumnViewController widthThatFits]
static CGFloat xpl_widthThatFits(id self, SEL _cmd) {
    if (CTmrEnabled) return CTmrLockedWidth;
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

    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    CGFloat w = [ud floatForKey:@"ColumnTamerPreviewWidth"];
    if (w >= 100.0 && w <= 2000.0) CTmrLockedWidth = w;

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
    NSLog(@"[ColumnTamer] ENABLED, locked preview width = %.0f", CTmrLockedWidth);
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
