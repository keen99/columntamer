// ColumnTamerMenu — menubar status item + prefs panel.
// Lives in user session (LSUIElement app). Writes defaults to com.apple.finder.
// Apply = write ColumnTamerMinWidth/MaxWidth + killall Finder (osax re-reads on relaunch).
// Start-at-login = manage its own LaunchAgent.

import Cocoa

let appBundleID = "com.local.columntamer.menu"
let loginAgentLabel = "com.local.columntamer.menu"
let loginAgentPlist = "/Library/LaunchAgents/com.local.columntamer.menu.plist"

@main
struct Main {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)   // no dock icon
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var prefsController: PrefsController?

    func applicationDidFinishLaunching(_ n: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        // SF Symbol: 3-column Finder view. Template = adapts to menubar tint.
        let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let icon = NSImage(systemSymbolName: "rectangle.split.3x1", accessibilityDescription: "ColumnTamer")!
        statusItem.button?.image = icon.withSymbolConfiguration(cfg)
        statusItem.button?.image?.isTemplate = true
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = "ColumnTamer"
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "ColumnTamer", action: nil, keyEquivalent: "").isEnabled = false
        menu.addItem(.separator())

        let p = NSMenuItem(title: "Preferences…", action: #selector(showPrefs), keyEquivalent: ",")
        p.target = self
        menu.addItem(p)

        menu.addItem(.separator())
        let q = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(q)

        statusItem.menu = menu
    }

    @objc func showPrefs() {
        if prefsController == nil {
            prefsController = PrefsController()
        }
        prefsController?.showWindow()
    }
}

// ---- defaults helpers -------------------------------------------------------

enum CTDefaults {
    static let domain = "com.apple.finder"
    static let minKey = "ColumnTamerMinWidth"
    static let maxKey = "ColumnTamerMaxWidth"

    static func readMin() -> CGFloat { defaultsFloat(minKey, default: 240) }
    static func readMax() -> CGFloat { defaultsFloat(maxKey, default: 350) }

    static func write(min mn: CGFloat, max mx: CGFloat) {
        let d = UserDefaults(suiteName: domain) ?? UserDefaults.standard
        d.set(Double(mn), forKey: minKey)
        d.set(Double(mx), forKey: maxKey)
    }

    static func defaultsFloat(_ key: String, default d: CGFloat) -> CGFloat {
        let ud = UserDefaults(suiteName: domain) ?? UserDefaults.standard
        let v = ud.float(forKey: key)
        return v == 0 ? d : CGFloat(v)
    }
}

// ---- start-at-login LaunchAgent ---------------------------------------------

enum CTLogin {
    // Source of truth = our own UserDefaults bool. launchctl enable/disable only
    // ENACTS the decision; we never parse launchctl output back (format varies
    // across macOS -> fragile). bootout would kill THIS app (it IS the agent
    // target); disable keeps the running instance alive, just blocks login relaunch.
    private static let key = "startAtLogin"
    private static let ud = UserDefaults.standard

    static var isEnabled: Bool {
        // first-launch default: ON (postinstall bootstraps agent enabled)
        if ud.object(forKey: key) == nil { return true }
        return ud.bool(forKey: key)
    }

    static func enable() {
        let uid = getuid()
        // ensure loaded first (bootstrap no-op if already loaded)
        _ = shellBool("/bin/launchctl bootstrap gui/\(uid) \(loginAgentPlist) 2>/dev/null")
        // enable flag. NO kickstart (would kill this running app).
        _ = shellBool("/bin/launchctl enable gui/\(uid)/\(loginAgentLabel)")
        ud.set(true, forKey: key)
    }

    static func disable() {
        // disable, NOT bootout -> app keeps running, just won't relaunch at login
        _ = shellBool("/bin/launchctl disable gui/\(getuid())/\(loginAgentLabel)")
        ud.set(false, forKey: key)
    }

    @discardableResult
    static func shellBool(_ cmd: String) -> Bool {
        let t = Process()
        t.launchPath = "/bin/zsh"
        t.arguments = ["-c", cmd]
        t.standardOutput = FileHandle(forWritingAtPath: "/dev/null")
        t.standardError = FileHandle(forWritingAtPath: "/dev/null")
        do { try t.run(); t.waitUntilExit() } catch { return false }
        return t.terminationStatus == 0
    }

}

// ---- prefs window -----------------------------------------------------------

final class PrefsController: NSObject, NSWindowDelegate, NSTextFieldDelegate {

    private var window: NSWindow!
    private var minField: NSTextField!
    private var maxField: NSTextField!
    private var loginBtn: NSButton!
    private var statusLabel: NSTextField!

    func showWindow() {
        if window == nil { build() }
        loadValues()
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private func build() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 230),
                         styleMask: [.titled, .closable],
                         backing: .buffered, defer: false)
        w.title = "ColumnTamer"
        w.delegate = self
        w.isReleasedWhenClosed = false
        window = w

        let c = NSStackView()
        c.orientation = .vertical
        c.alignment = .leading
        c.spacing = 12
        c.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        c.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "Preview pane width range (px)")
        title.font = .boldSystemFont(ofSize: 12)

        let rowMin = labeledRow("Minimum:", tag: 1, initial: "")
        minField = rowMin.field
        let rowMax = labeledRow("Maximum:", tag: 2, initial: "")
        maxField = rowMax.field

        loginBtn = NSButton(checkboxWithTitle: "Start ColumnTamer at login",
                            target: self, action: #selector(toggleLogin))
        loginBtn.state = CTLogin.isEnabled ? .on : .off

        statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = .systemFont(ofSize: 10)
        statusLabel.textColor = .secondaryLabelColor

        let applyBtn = NSButton(title: "Apply",
                                target: self, action: #selector(apply))
        applyBtn.bezelStyle = .rounded
        applyBtn.keyEquivalent = ""

        c.addArrangedSubview(title)
        c.addArrangedSubview(rowMin.view)
        c.addArrangedSubview(rowMax.view)
        c.addArrangedSubview(loginBtn)
        c.addArrangedSubview(statusLabel)
        c.addArrangedSubview(applyBtn)

        let content = w.contentView!
        content.addSubview(c)
        NSLayoutConstraint.activate([
            c.topAnchor.constraint(equalTo: content.topAnchor),
            c.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            c.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            c.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
    }

    private struct RowResult { let view: NSView; let field: NSTextField }

    private func labeledRow(_ label: String, tag: Int, initial: String) -> RowResult {
        let h = NSStackView()
        h.orientation = .horizontal
        h.spacing = 8
        let l = NSTextField(labelWithString: label)
        l.alignment = .right
        let f = NSTextField(string: initial)
        f.tag = tag
        f.delegate = self
        f.translatesAutoresizingMaskIntoConstraints = false
        f.widthAnchor.constraint(equalToConstant: 70).isActive = true
        h.addArrangedSubview(l)
        h.addArrangedSubview(f)
        let spacer = NSView()
        h.addArrangedSubview(spacer)
        return RowResult(view: h, field: f)
    }

    private func loadValues() {
        minField.intValue = Int32(CTDefaults.readMin())
        maxField.intValue = Int32(CTDefaults.readMax())
        loginBtn.state = CTLogin.isEnabled ? .on : .off
    }

    @objc func toggleLogin() {
        if loginBtn.state == .on {
            CTLogin.enable()
            statusLabel.stringValue = CTLogin.isEnabled ? "Will start at login." : "Enable failed."
        } else {
            CTLogin.disable()
            statusLabel.stringValue = "Will not start at login."
        }
    }

    @objc func apply() {
        let mn = CGFloat(minField.intValue)
        let mx = CGFloat(maxField.intValue)
        guard mn >= 240, mx >= 240, mn <= mx, mx <= 6000 else {
            statusLabel.stringValue = "Need 240–6000, min ≤ max."
            return
        }
        // No sub-floor warning needed: 240 is the hard limit below which Finder
        // ignores the clamp (preview pane intrinsic width). Enforced here.
        CTDefaults.write(min: mn, max: mx)
        // post distributed notification -> osax re-reads prefs live, no Finder restart
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDistributedCenter(),
            CFNotificationName("com.local.columntamer.prefsChanged" as CFString),
            nil, nil, true)
        statusLabel.stringValue = "Applied."
    }
}
