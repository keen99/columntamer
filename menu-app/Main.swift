// ColumnTamerMenu — menubar status item + prefs panel.
// Lives in user session (LSUIElement app). Writes defaults to com.apple.finder.
// Apply = write ColumnTamerMinWidth/MaxWidth + killall Finder (osax re-reads on relaunch).
// Start-at-login = manage its own LaunchAgent.

import Cocoa
import Darwin

let appBundleID = "columntamer.menu"
let loginAgentLabel = "columntamer.menu"
let loginAgentPlist = "/Library/LaunchAgents/columntamer.menu.plist"
// single-instance: named lock + activate notification
let ctActivateNote = "columntamer.menu.activate"

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
    // H2 health: last osax ack. nil = osax not loaded (no Finder inject yet).
    private var lastHealth: Date? = nil
    static var sharedHealth: Date? = nil   // diagnostics reads this

    func applicationDidFinishLaunching(_ n: Notification) {
        // Single-instance: rely on launchd Label (one per Label by design).
        // Duplicate launch path (manual `open`) = rare; distributed ping below
        // activates existing instance if it's listening.

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
                app.buildMenu()
            },
            "columntamer.health" as CFString,
            nil,
            .deliverImmediately)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        // Draw icon in code (B): rounded rect + 2 dividers, matching
        // rectangle.split.3x1. Template = adapts to menubar tint. No SF dep,
        // no asset, works all macOS.
        statusItem.button?.image = columnTamerIcon()
        statusItem.button?.image?.isTemplate = true
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = "ColumnTamer"
        buildMenu()
    }

    // Landscape glyph matching SF rectangle.split.3x1 proportions.
    private func columnTamerIcon() -> NSImage {
        let w: CGFloat = 20, h: CGFloat = 14
        let img = NSImage(size: NSSize(width: w, height: h))
        img.lockFocus()
        NSColor.black.setStroke()
        NSColor.black.setFill()
        let inset: CGFloat = 1.0
        let lw: CGFloat = 1.5
        let frame = NSRect(x: inset, y: inset,
                           width: w - inset*2, height: h - inset*2)
        let r = NSBezierPath(roundedRect: frame, xRadius: 2, yRadius: 2)
        r.lineWidth = lw
        r.stroke()
        // 2 vertical dividers at thirds, thin for wide columns
        let third = frame.width / 3
        let x1 = frame.minX + third
        let x2 = frame.minX + third * 2
        let divW: CGFloat = 1.6
        NSRect(x: x1 - divW/2, y: frame.minY, width: divW, height: frame.height).fill()
        NSRect(x: x2 - divW/2, y: frame.minY, width: divW, height: frame.height).fill()
        img.unlockFocus()
        img.isTemplate = true
        return img
    }

    private func buildMenu() {
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

        let a = NSMenuItem(title: "About ColumnTamer", action: #selector(showAbout), keyEquivalent: "")
        a.target = self
        menu.addItem(a)

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

    @objc func showAbout() {
        AboutPanel.show()
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
    static let asMinKey = "ColumnTamerAutosizeMin"
    static let asMaxKey = "ColumnTamerAutosizeMax"
    static let asPadKey = "ColumnTamerAutosizePadding"
    static let asEnKey  = "ColumnTamerAutosizeEnabled"

    static func readMin() -> CGFloat { defaultsFloat(minKey, default: 240) }
    static func readMax() -> CGFloat { defaultsFloat(maxKey, default: 350) }
    static func readAsMin() -> CGFloat { defaultsFloat(asMinKey, default: 120) }
    static func readAsMax() -> CGFloat { defaultsFloat(asMaxKey, default: 2000) }
    static func readAsPad() -> CGFloat { max(12, defaultsFloat(asPadKey, default: 16)) }
    static func readAsEn() -> Bool { defaultsBool(asEnKey, default: true) }

    static func write(min mn: CGFloat, max mx: CGFloat) {
        let d = UserDefaults(suiteName: domain) ?? UserDefaults.standard
        d.set(Double(mn), forKey: minKey)
        d.set(Double(mx), forKey: maxKey)
    }

    static func writeAutosize(enabled en: Bool, min mn: CGFloat, max mx: CGFloat, pad: CGFloat) {
        let d = UserDefaults(suiteName: domain) ?? UserDefaults.standard
        d.set(en, forKey: asEnKey)
        d.set(Double(mn), forKey: asMinKey)
        d.set(Double(mx), forKey: asMaxKey)
        d.set(Double(pad), forKey: asPadKey)
        d.synchronize()
    }

    static func defaultsFloat(_ key: String, default d: CGFloat) -> CGFloat {
        let ud = UserDefaults(suiteName: domain) ?? UserDefaults.standard
        guard let value = ud.object(forKey: key) as? NSNumber else { return d }
        return CGFloat(value.doubleValue)
    }

    static func defaultsBool(_ key: String, default d: Bool) -> Bool {
        let ud = UserDefaults(suiteName: domain) ?? UserDefaults.standard
        return ud.object(forKey: key) != nil ? ud.bool(forKey: key) : d
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
    // autosize
    private var asEnBtn: NSButton!
    private var asMinField: NSTextField!
    private var asMaxField: NSTextField!
    private var asPadField: NSTextField!

    func showWindow() {
        if window == nil { build() }
        loadValues()
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private func build() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 470),
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

        // ── Preview pane ──
        let prevTitle = NSTextField(labelWithString: "Preview pane width")
        prevTitle.font = .boldSystemFont(ofSize: 12)
        let prevHelp = helpLabel("Minimum and maximum constrain preview pane width. Values use macOS points, not characters. Allowed range: 240–6000 pt.")

        let rowMin = labeledRow("Minimum (pt):", tag: 1, initial: "", range: 240...6000)
        minField = rowMin.field
        let rowMax = labeledRow("Maximum (pt):", tag: 2, initial: "", range: 240...6000)
        maxField = rowMax.field

        // ── Column autosize ──
        let asTitle = NSTextField(labelWithString: "Column width autosize")
        asTitle.font = .boldSystemFont(ofSize: 12)
        let asHelp = helpLabel("Fits each column to its longest filename. Trailing space is blank room after the filename and prevents clipping. Width range: 0–6000 pt; trailing-space range: 12–200 pt. Finder may enforce a larger internal minimum.")

        asEnBtn = NSButton(checkboxWithTitle: "Enable column autosize",
                           target: self, action: nil)
        asEnBtn.state = CTDefaults.readAsEn() ? .on : .off

        let rowAsMin = labeledRow("Minimum (pt):", tag: 3, initial: "", range: 0...6000)
        asMinField = rowAsMin.field
        let rowAsMax = labeledRow("Maximum (pt):", tag: 4, initial: "", range: 0...6000)
        asMaxField = rowAsMax.field
        let rowAsPad = labeledRow("Trailing space (pt):", tag: 5, initial: "", range: 12...200)
        asPadField = rowAsPad.field

        // ── Login ──
        loginBtn = NSButton(checkboxWithTitle: "Start at login",
                            target: self, action: #selector(toggleLogin))
        loginBtn.state = CTLogin.isEnabled ? .on : .off

        statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = .systemFont(ofSize: 10)
        statusLabel.textColor = .secondaryLabelColor

        let applyBtn = NSButton(title: "Apply",
                                target: self, action: #selector(apply))
        applyBtn.bezelStyle = .rounded
        applyBtn.keyEquivalent = ""

        c.addArrangedSubview(prevTitle)
        c.addArrangedSubview(prevHelp)
        c.addArrangedSubview(rowMin.view)
        c.addArrangedSubview(rowMax.view)
        c.addArrangedSubview(NSView()) // spacer
        c.addArrangedSubview(asTitle)
        c.addArrangedSubview(asHelp)
        c.addArrangedSubview(asEnBtn)
        c.addArrangedSubview(rowAsMin.view)
        c.addArrangedSubview(rowAsMax.view)
        c.addArrangedSubview(rowAsPad.view)
        c.addArrangedSubview(NSView())
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

    private func helpLabel(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 10)
        label.textColor = .secondaryLabelColor
        label.preferredMaxLayoutWidth = 330
        return label
    }

    private func labeledRow(_ label: String, tag: Int, initial: String,
                            range: ClosedRange<Int>) -> RowResult {
        let h = NSStackView()
        h.orientation = .horizontal
        h.spacing = 8
        let l = NSTextField(labelWithString: label)
        l.alignment = .right
        let f = NSTextField(string: initial)
        f.tag = tag
        f.delegate = self
        f.toolTip = "Allowed: \(range.lowerBound)–\(range.upperBound) points"
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
        asEnBtn.state = CTDefaults.readAsEn() ? .on : .off
        asMinField.intValue = Int32(CTDefaults.readAsMin())
        asMaxField.intValue = Int32(CTDefaults.readAsMax())
        asPadField.intValue = Int32(CTDefaults.readAsPad())
        loginBtn.state = CTLogin.isEnabled ? .on : .off
    }

    // Live filter: digits only. Range checks happen when editing ends, allowing
    // partial values such as 3 -> 30 -> 300 in preview fields.
    func controlTextDidChange(_ n: Notification) {
        guard let f = n.object as? NSTextField else { return }
        let digits = f.stringValue.filter { $0.isNumber }
        if digits != f.stringValue { f.stringValue = digits }
    }

    func control(_ control: NSControl, textShouldEndEditing fieldEditor: NSText) -> Bool {
        guard let field = control as? NSTextField,
              let value = Int(field.stringValue) else {
            statusLabel.stringValue = "Enter a whole number."
            NSSound.beep()
            return false
        }
        let allowed: ClosedRange<Int>
        switch field.tag {
        case 1, 2: allowed = 240...6000
        case 3, 4: allowed = 0...6000
        case 5: allowed = 12...200
        default: return true
        }
        guard allowed.contains(value) else {
            statusLabel.stringValue = "Allowed: \(allowed.lowerBound)–\(allowed.upperBound) pt."
            NSSound.beep()
            return false
        }
        return true
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
        // Commit active field editor before reading intValue.
        guard window.makeFirstResponder(nil) else {
            statusLabel.stringValue = "Finish editing field, then Apply."
            return
        }
        let mn = CGFloat(minField.intValue)
        let mx = CGFloat(maxField.intValue)
        let asMn = CGFloat(asMinField.intValue)
        let asMx = CGFloat(asMaxField.intValue)
        let asPad = CGFloat(asPadField.intValue)
        guard mn >= 240, mx >= 240, mn <= mx, mx <= 6000 else {
            statusLabel.stringValue = "Preview clamp need 240-6000, min ≤ max."
            return
        }
        guard asMn >= 0, asMx <= 6000, asMn <= asMx, asPad >= 12, asPad <= 200 else {
            statusLabel.stringValue = "Autosize bounds invalid."
            return
        }
        CTDefaults.write(min: mn, max: mx)
        CTDefaults.writeAutosize(enabled: asEnBtn.state == .on, min: asMn, max: asMx, pad: asPad)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDistributedCenter(),
            CFNotificationName("columntamer.prefsChanged" as CFString),
            nil, nil, true)
        let state = asEnBtn.state == .on ? "on" : "off"
        statusLabel.stringValue = "Applied: autosize \(state), \(Int(asMn))–\(Int(asMx)) pt, trailing \(Int(asPad)) pt."
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
        kv("helper", shell("/bin/launchctl list columntamer.helper 2>&1 | /usr/bin/head -5").trimmingCharacters(in: .whitespacesAndNewlines))
        kv("menu", shell("/bin/launchctl list columntamer.menu 2>&1 | /usr/bin/head -5").trimmingCharacters(in: .whitespacesAndNewlines))
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

// MARK: - About Panel
enum AboutPanel {
    private static var retained: NSWindowController?

    static func show() {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let commit = info?["GitCommit"] as? String ?? "dev"
        let branch = info?["GitBranch"] as? String ?? "dev"
        let date = info?["BuildDate"] as? String ?? "dev"

        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 220),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "About ColumnTamer"
        w.center()

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        w.contentView = stack
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: w.contentView!.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: w.contentView!.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: w.contentView!.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: w.contentView!.trailingAnchor, constant: -20),
        ])

        let title = NSTextField(labelWithString: "ColumnTamer")
        title.font = NSFont.boldSystemFont(ofSize: 22)
        stack.addArrangedSubview(title)

        func row(_ k: String, _ v: String) -> NSView {
            let l = NSTextField(labelWithString: k)
            l.font = NSFont.systemFont(ofSize: 11)
            l.textColor = .secondaryLabelColor
            l.alignment = .right
            let r = NSTextField(labelWithString: v)
            r.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            let h = NSStackView(views: [l, r])
            h.orientation = .horizontal
            h.spacing = 8
            return h
        }
        stack.addArrangedSubview(row("Version", version))
        stack.addArrangedSubview(row("Build",   build))
        stack.addArrangedSubview(row("Commit",  commit))
        stack.addArrangedSubview(row("Branch",  branch))
        stack.addArrangedSubview(row("Built",   date))

        NSApp.activate(ignoringOtherApps: true)
        retained = NSWindowController(window: w)
        retained?.showWindow(nil)
        w.makeKeyAndOrderFront(nil)
    }
}
