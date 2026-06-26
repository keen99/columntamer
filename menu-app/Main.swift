// ColumnTamerMenu — menubar status item + prefs panel.
// Lives in user session (LSUIElement app). Writes defaults to com.apple.finder.
// Apply = write ColumnTamerMinWidth/MaxWidth + killall Finder (osax re-reads on relaunch).
// Start-at-login = manage its own LaunchAgent.

import Cocoa
import Darwin

let appBundleID = "com.local.columntamer.menu"
let loginAgentLabel = "com.local.columntamer.menu"
let loginAgentPlist = "/Library/LaunchAgents/com.local.columntamer.menu.plist"
// single-instance: named lock + activate notification
let ctActivateNote = "com.local.columntamer.menu.activate"

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
    // single-instance guard: hold lock file fd open for app lifetime
    private static var lockFD: Int32 = -1
    // H2 health: last osax ack. nil = osax not loaded (no Finder inject yet).
    private var lastHealth: Date? = nil
    static var sharedHealth: Date? = nil   // diagnostics reads this

    func applicationDidFinishLaunching(_ n: Notification) {
        // single-instance check: try exclusive lock on sentinel
        let sentinel = "/tmp/.columntamer.menu.lock"
        let fd = open(sentinel, O_CREAT | O_RDWR, 0o644)
        if fd >= 0 {
            if flock(fd, LOCK_EX | LOCK_NB) == 0 {
                AppDelegate.lockFD = fd   // hold open for lifetime
            } else {
                // another instance holds lock -> ping it to activate, then quit
                CFNotificationCenterPostNotification(
                    CFNotificationCenterGetDistributedCenter(),
                    CFNotificationName(ctActivateNote as CFString),
                    nil, nil, true)
                NSApp.terminate(nil)
                return
            }
        }

        // listen for activate pings from late arrivals
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDistributedCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { (_, observer, _, _, _) in
                guard let observer = observer else { return }
                let app = Unmanaged<AppDelegate>.fromOpaque(observer).takeUnretainedValue()
                app.showPrefs()
            },
            ctActivateNote as CFString,
            nil,
            .deliverImmediately)

        // H2: listen for osax health acks
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDistributedCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { (_, observer, _, _, info) in
                guard let observer = observer else { return }
                let app = Unmanaged<AppDelegate>.fromOpaque(observer).takeUnretainedValue()
                app.lastHealth = Date()
                AppDelegate.sharedHealth = app.lastHealth
                app.rebuildMenu()
            },
            "com.local.columntamer.health" as CFString,
            nil,
            .deliverImmediately)

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
        // H2: osax active state
        let healthItem: NSMenuItem
        if let h = lastHealth {
            let age = Int(Date().timeIntervalSince(h))
            let ageStr = age < 60 ? "\(age)s ago" : "\(age/60)m ago"
            healthItem = NSMenuItem(title: "ColumnTamer: active (\(ageStr))", action: nil, keyEquivalent: "")
        } else {
            healthItem = NSMenuItem(title: "ColumnTamer: inactive (restart Finder)", action: #selector(restartFinder), keyEquivalent: "")
            healthItem.target = self
        }
        healthItem.isEnabled = (lastHealth == nil)  // clickable only if inactive (to restart)
        menu.addItem(healthItem)
        menu.addItem(.separator())

        let p = NSMenuItem(title: "Preferences…", action: #selector(showPrefs), keyEquivalent: "")
        p.target = self
        menu.addItem(p)

        let d = NSMenuItem(title: "Diagnostics…", action: #selector(showDiagnostics), keyEquivalent: "")
        d.target = self
        menu.addItem(d)

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

    @objc func showDiagnostics() {
        DiagnosticsController.shared.showWindow()
    }

    @objc func restartFinder() {
        // user clicked inactive status -> restart Finder to trigger inject
        let t = Process()
        t.launchPath = "/usr/bin/killall"
        t.arguments = ["Finder"]
        try? t.run()
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

    // live filter: digits only. No range clamp live (rewriting stringValue
    // resets cursor mid-type = typing fight). Range enforced on Apply.
    func controlTextDidChange(_ n: Notification) {
        guard let f = n.object as? NSTextField else { return }
        let digits = f.stringValue.filter { $0.isNumber }
        if digits != f.stringValue { f.stringValue = digits }
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

// ---- diagnostics window -----------------------------------------------------
// Gathers system state for self-serve debugging when osax fails to load.

final class DiagnosticsController: NSObject, NSWindowDelegate {

    static let shared = DiagnosticsController()
    private var window: NSWindow!
    private var textView: NSTextView!
    private var report = ""

    func showWindow() {
        if window == nil { build() }
        gather()
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private func build() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 600),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable],
                         backing: .buffered, defer: false)
        w.title = "ColumnTamer Diagnostics"
        w.delegate = self
        w.isReleasedWhenClosed = false
        window = w

        let cv = w.contentView!

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.maxSize = NSSize(width: 99999, height: 99999)
        textView.autoresizingMask = [.width]
        scroll.documentView = textView
        cv.addSubview(scroll)

        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(row)

        let refreshBtn = NSButton(title: "Refresh", target: self, action: #selector(refresh))
        refreshBtn.bezelStyle = .rounded
        refreshBtn.translatesAutoresizingMaskIntoConstraints = false
        let copyBtn = NSButton(title: "Copy to Clipboard", target: self, action: #selector(copyReport))
        copyBtn.bezelStyle = .rounded
        copyBtn.translatesAutoresizingMaskIntoConstraints = false
        let saveBtn = NSButton(title: "Save…", target: self, action: #selector(saveReport))
        saveBtn.bezelStyle = .rounded
        saveBtn.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(refreshBtn)
        row.addSubview(copyBtn)
        row.addSubview(saveBtn)

        let btnH: CGFloat = 24, pad: CGFloat = 12, rowH: CGFloat = 36
        NSLayoutConstraint.activate([
            // scroll fills top, above button row
            scroll.topAnchor.constraint(equalTo: cv.topAnchor, constant: pad),
            scroll.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: pad),
            scroll.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -pad),
            scroll.bottomAnchor.constraint(equalTo: row.topAnchor, constant: -pad),
            // button row pinned to bottom
            row.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: pad),
            row.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -pad),
            row.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -pad),
            row.heightAnchor.constraint(equalToConstant: rowH),
            // buttons left-aligned in row, vertically centered
            refreshBtn.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            refreshBtn.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            copyBtn.leadingAnchor.constraint(equalTo: refreshBtn.trailingAnchor, constant: 8),
            copyBtn.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            saveBtn.leadingAnchor.constraint(equalTo: copyBtn.trailingAnchor, constant: 8),
            saveBtn.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])
        _ = btnH
    }

    @objc func refresh() { gather() }

    @objc func copyReport() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
    }

    @objc func saveReport() {
        let panel = NSSavePanel()
        panel.title = "Save ColumnTamer Diagnostics"
        panel.nameFieldStringValue = "ColumnTamer-diagnostics.txt"
        if panel.runModal() == .OK, let url = panel.url {
            try? report.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func shell(_ cmd: String) -> String {
        let t = Process()
        let p = Pipe()
        t.launchPath = "/bin/zsh"
        t.arguments = ["-c", cmd]
        t.standardOutput = p
        t.standardError = p
        do { try t.run(); t.waitUntilExit() } catch { return "(error: \(error))" }
        return String(data: p.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    private func section(_ title: String) { report += "\n=== \(title) ===\n" }
    private func kv(_ k: String, _ v: String) { report += "\(k): \(v)\n" }

    private func gather() {
        report = "ColumnTamer Diagnostics — \(Date())\n"

        section("System")
        kv("macOS", shell("sw_vers -productVersion").trimmingCharacters(in: .whitespacesAndNewlines))
        kv("arch", shell("uname -m").trimmingCharacters(in: .whitespacesAndNewlines))

        section("Security")
        kv("SIP", shell("/usr/bin/csrutil status").trimmingCharacters(in: .whitespacesAndNewlines))
        kv("boot-args", shell("/usr/sbin/nvram boot-args 2>/dev/null").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "(none)" : shell("/usr/sbin/nvram boot-args 2>/dev/null").trimmingCharacters(in: .whitespacesAndNewlines))

        section("Osax")
        let osax = "/Library/ScriptingAdditions/ColumnTamer.osax"
        kv("path", osax)
        let ls = shell("/bin/ls -ld \(osax) 2>&1").trimmingCharacters(in: .whitespacesAndNewlines)
        kv("exists", ls.contains("No such") ? "NO" : "yes")
        kv("stat", ls)
        kv("codesign", shell("/usr/bin/codesign -dv \(osax) 2>&1").trimmingCharacters(in: .whitespacesAndNewlines))

        section("Agents")
        kv("helper", shell("/bin/launchctl list com.local.columntamer.helper 2>&1 | /usr/bin/head -5").trimmingCharacters(in: .whitespacesAndNewlines))
        kv("menu", shell("/bin/launchctl list com.local.columntamer.menu 2>&1 | /usr/bin/head -5").trimmingCharacters(in: .whitespacesAndNewlines))
        kv("helper log", "~/Library/Logs/ColumnTamer/ColumnTamerHelper.log")
        kv("helper log tail", shell("/usr/bin/tail -20 ~/Library/Logs/ColumnTamer/ColumnTamerHelper.log 2>&1").trimmingCharacters(in: .whitespacesAndNewlines))

        section("Finder")
        kv("pid", shell("/usr/bin/pgrep -x Finder").trimmingCharacters(in: .whitespacesAndNewlines))
        kv("ColumnTamer log (last 2m)", shell("/usr/bin/log show --predicate 'process==\"Finder\"' --last 2m 2>&1 | /usr/bin/grep ColumnTamer | /usr/bin/tail -20").trimmingCharacters(in: .whitespacesAndNewlines))

        section("Health (menu app view)")
        if let h = AppDelegate.sharedHealth {
            kv("last osax ack", "\(h) (\(Int(Date().timeIntervalSince(h)))s ago)")
        } else {
            kv("last osax ack", "NEVER — osax not loaded or health not received")
        }

        section("Prefs")
        kv("ColumnTamerMinWidth", shell("/usr/bin/defaults read com.apple.finder ColumnTamerMinWidth 2>&1").trimmingCharacters(in: .whitespacesAndNewlines))
        kv("ColumnTamerMaxWidth", shell("/usr/bin/defaults read com.apple.finder ColumnTamerMaxWidth 2>&1").trimmingCharacters(in: .whitespacesAndNewlines))

        textView.string = report
    }
}
