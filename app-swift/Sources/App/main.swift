import AppKit

final class FlippedContainerView: NSView {
    override var isFlipped: Bool { true }
}

final class VisibilityStore {
    private let hiddenBundleDefaultsKey = "FrostBar.HiddenBundleIDs"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func hiddenBundleIDs() -> Set<String> {
        let values = defaults.array(forKey: hiddenBundleDefaultsKey) as? [String] ?? []
        return Set(values)
    }

    func isVisible(bundleID: String) -> Bool {
        !hiddenBundleIDs().contains(bundleID)
    }

    func setVisible(_ isVisible: Bool, for bundleID: String) {
        var hidden = hiddenBundleIDs()
        if isVisible {
            hidden.remove(bundleID)
        } else {
            hidden.insert(bundleID)
        }
        defaults.set(Array(hidden).sorted(), forKey: hiddenBundleDefaultsKey)
    }
}

private struct ListedAppEntry {
    let app: NSRunningApplication
    let displayName: String
    let bundleID: String
    let icon: NSImage?
}

final class AppActivationTarget: NSObject {
    let pid: pid_t
    let bundleID: String
    let bundleURL: URL?
    let appName: String

    init(app: NSRunningApplication, bundleID: String) {
        self.pid = app.processIdentifier
        self.bundleID = bundleID
        self.bundleURL = app.bundleURL
        self.appName = app.localizedName ?? bundleID
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private let dynamicItemTag = 1001
    private let emptyItemTag = 1002
    private let settingsItemTag = 1003
    private let maxMenuItems = 40

    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var settingsScrollView: NSScrollView?
    private var settingsListStack: NSStackView?
    private var controlToBundleID: [Int: String] = [:]
    private var controlTagSeed = 2000

    private let visibilityStore = VisibilityStore()

    private let helperKeywords = [
        "helper", "daemon", "agent", "plugin", "service", "renderer", "crashpad", "gpu",
        "xpc", "loginitem", "updater", "launcher", "widget", "extension"
    ]
    private let accessoryAllowKeywords = [
        "uu", "quark", "v2ray", "wechat", "tencent"
    ]
    private let excludedBundleIDs = Set([
        "com.apple.finder",
        "com.apple.controlcenter",
        "com.apple.systemuiserver",
        "com.apple.notificationcenterui"
    ])

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "●"

        let menu = NSMenu()
        menu.delegate = self

        let empty = NSMenuItem(title: "No running apps", action: nil, keyEquivalent: "")
        empty.tag = emptyItemTag
        empty.isHidden = true
        menu.addItem(empty)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.tag = settingsItemTag
        settingsItem.target = self
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(title: "Quit FrostBar", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item

        refreshMenuItems()
    }

    func menuWillOpen(_ menu: NSMenu) {
        statusItem?.button?.title = "○"
        refreshMenuItems()
    }

    func menuDidClose(_ menu: NSMenu) {
        statusItem?.button?.title = "●"
    }

    @objc private func openSettings() {
        // Run after menu tracking finishes to avoid occasional no-response clicks.
        DispatchQueue.main.async { [weak self] in
            self?.presentSettingsWindow()
        }
    }

    private func presentSettingsWindow() {
        if let window = settingsWindow,
           window.contentView != nil {
            reloadSettingsRows()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "FrostBar Settings"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        let root = NSStackView()
        root.translatesAutoresizingMaskIntoConstraints = false
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 12

        let intro = NSTextField(labelWithString: "Control whether each running app appears in FrostBar menu list.")
        intro.lineBreakMode = .byWordWrapping
        intro.maximumNumberOfLines = 0
        intro.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        root.addArrangedSubview(intro)

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        settingsScrollView = scrollView

        let listStack = NSStackView()
        listStack.translatesAutoresizingMaskIntoConstraints = false
        listStack.orientation = .vertical
        listStack.alignment = .leading
        listStack.spacing = 8
        listStack.setHuggingPriority(.required, for: .vertical)
        listStack.setContentCompressionResistancePriority(.required, for: .vertical)
        settingsListStack = listStack

        let documentView = FlippedContainerView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(listStack)
        NSLayoutConstraint.activate([
            listStack.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 8),
            listStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 8),
            listStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -8),
            listStack.bottomAnchor.constraint(lessThanOrEqualTo: documentView.bottomAnchor, constant: -8),
            listStack.widthAnchor.constraint(equalTo: documentView.widthAnchor, constant: -16)
        ])
        scrollView.documentView = documentView
        root.addArrangedSubview(scrollView)

        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 360)
        ])

        window.contentView = content
        settingsWindow = window
        reloadSettingsRows()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        guard let win = notification.object as? NSWindow,
              win === settingsWindow else {
            return
        }

        // Prevent stale UI references from being reused on next Settings open.
        settingsWindow = nil
        settingsScrollView = nil
        settingsListStack = nil
        controlToBundleID.removeAll()
    }

    private func reloadSettingsRows() {
        guard let stack = settingsListStack else {
            return
        }

        controlToBundleID.removeAll()
        for subview in stack.arrangedSubviews {
            stack.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }

        let entries = discoverRunningApps()
        if entries.isEmpty {
            stack.addArrangedSubview(NSTextField(labelWithString: "No running apps"))
            return
        }

        for entry in entries {
            stack.addArrangedSubview(makeSettingsRow(for: entry))
        }

        scrollSettingsToTop()
    }

    private func scrollSettingsToTop() {
        guard let scrollView = settingsScrollView else {
            return
        }

        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func makeSettingsRow(for entry: ListedAppEntry) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8

        let iconHolder = NSView(frame: NSRect(x: 0, y: 0, width: 16, height: 16))
        iconHolder.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconHolder.widthAnchor.constraint(equalToConstant: 16),
            iconHolder.heightAnchor.constraint(equalToConstant: 16)
        ])
        if let icon = entry.icon {
            let iconView = NSImageView()
            let sizedIcon = icon.copy() as? NSImage ?? icon
            sizedIcon.size = NSSize(width: 14, height: 14)
            iconView.image = sizedIcon
            iconView.translatesAutoresizingMaskIntoConstraints = false
            iconHolder.addSubview(iconView)
            NSLayoutConstraint.activate([
                iconView.centerXAnchor.constraint(equalTo: iconHolder.centerXAnchor),
                iconView.centerYAnchor.constraint(equalTo: iconHolder.centerYAnchor),
                iconView.widthAnchor.constraint(equalToConstant: 14),
                iconView.heightAnchor.constraint(equalToConstant: 14)
            ])
        }
        row.addArrangedSubview(iconHolder)

        let name = NSTextField(labelWithString: entry.displayName)
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        name.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(name)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(spacer)

        let checkbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleVisibility(_:)))
        checkbox.controlSize = .small
        checkbox.state = visibilityStore.isVisible(bundleID: entry.bundleID) ? .on : .off
        controlTagSeed += 1
        checkbox.tag = controlTagSeed
        controlToBundleID[checkbox.tag] = entry.bundleID

        let toggleLabel = NSTextField(labelWithString: "Show in list")
        toggleLabel.alignment = .left
        let toggleStack = NSStackView(views: [checkbox, toggleLabel])
        toggleStack.orientation = .horizontal
        toggleStack.alignment = .centerY
        toggleStack.spacing = 4
        toggleStack.setContentHuggingPriority(.required, for: .horizontal)
        toggleStack.setContentCompressionResistancePriority(.required, for: .horizontal)
        row.addArrangedSubview(toggleStack)

        return row
    }

    @objc private func toggleVisibility(_ sender: NSButton) {
        guard let bundleID = controlToBundleID[sender.tag] else {
            return
        }

        visibilityStore.setVisible(sender.state == .on, for: bundleID)
        refreshMenuItems()
        reloadSettingsRows()
    }

    private func refreshMenuItems() {
        guard let menu = statusItem?.menu else {
            return
        }

        removeDynamicMenuItems(from: menu)

        let hidden = visibilityStore.hiddenBundleIDs()
        let visibleEntries = discoverRunningApps().filter { !hidden.contains($0.bundleID) }

        if visibleEntries.isEmpty {
            menu.item(withTag: emptyItemTag)?.isHidden = false
            return
        }

        menu.item(withTag: emptyItemTag)?.isHidden = true

        for (offset, entry) in visibleEntries.enumerated() {
            let item = NSMenuItem(title: entry.displayName, action: #selector(openAppWindow(_:)), keyEquivalent: "")
            item.tag = dynamicItemTag
            item.target = self
            item.image = entry.icon
            item.representedObject = AppActivationTarget(app: entry.app, bundleID: entry.bundleID)
            menu.insertItem(item, at: offset)
        }
    }

    @objc private func openAppWindow(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? AppActivationTarget else {
            return
        }

        let family = appFamily(bundleID: target.bundleID)
        let candidates = NSRunningApplication.runningApplications(withBundleIdentifier: target.bundleID)
            .filter { !$0.isTerminated }

        let best = pickBestActivationCandidate(from: candidates, preferredPID: target.pid)

        if let best, activateRunningApp(app: best), visibleWindowCount(for: best.processIdentifier) > 0 {
            return
        }

        if activateRunningApp(pid: target.pid),
           let preferred = NSRunningApplication(processIdentifier: target.pid),
           visibleWindowCount(for: preferred.processIdentifier) > 0 {
            return
        }

        _ = activateByAppleScript(bundleID: target.bundleID)
        _ = activateByAppleScript(appName: target.appName)

        if shouldReopenAfterActivate(family) || candidates.isEmpty || candidates.contains(where: { visibleWindowCount(for: $0.processIdentifier) == 0 }) {
            _ = reopenByAppleScript(bundleID: target.bundleID)
            _ = reopenByAppleScript(appName: target.appName)
        }

        if let bundleURL = target.bundleURL {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: bundleURL, configuration: config) { _, _ in }
        } else if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: target.bundleID) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, _ in }
        }
    }

    private func pickBestActivationCandidate(from apps: [NSRunningApplication], preferredPID: pid_t) -> NSRunningApplication? {
        guard !apps.isEmpty else {
            return nil
        }

        return apps.max { lhs, rhs in
            activationRank(lhs, preferredPID: preferredPID) < activationRank(rhs, preferredPID: preferredPID)
        }
    }

    private func activationRank(_ app: NSRunningApplication, preferredPID: pid_t) -> Int {
        var score = 0
        if app.processIdentifier == preferredPID { score += 1000 }
        if app.activationPolicy == .regular { score += 200 }
        if !app.isHidden { score += 30 }
        score += min(visibleWindowCount(for: app.processIdentifier), 5) * 60
        return score
    }

    private enum AppFamily {
        case quark
        case wechat
        case other
    }

    private func appFamily(bundleID: String) -> AppFamily {
        let lower = bundleID.lowercased()
        if lower.contains("quark") {
            return .quark
        }
        if lower.contains("wechat") || lower.contains("tencent") {
            return .wechat
        }
        return .other
    }

    private func shouldReopenAfterActivate(_ family: AppFamily) -> Bool {
        switch family {
        case .quark, .wechat:
            return true
        case .other:
            return false
        }
    }

    private func activateByAppleScript(bundleID: String) -> Bool {
        runAppleScript("tell application id \"\(bundleID)\" to activate")
    }

    private func activateByAppleScript(appName: String) -> Bool {
        runAppleScript("tell application \"\(appName)\" to activate")
    }

    private func reopenByAppleScript(bundleID: String) -> Bool {
        runAppleScript("tell application id \"\(bundleID)\" to reopen")
    }

    private func reopenByAppleScript(appName: String) -> Bool {
        runAppleScript("tell application \"\(appName)\" to reopen")
    }

    private func runAppleScript(_ source: String) -> Bool {
        var errorInfo: NSDictionary?
        let script = NSAppleScript(source: source)
        _ = script?.executeAndReturnError(&errorInfo)
        return errorInfo == nil
    }

    private func activateRunningApp(pid: pid_t) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else {
            return false
        }

        return activateRunningApp(app: app)
    }

    private func activateRunningApp(app: NSRunningApplication) -> Bool {
        guard !app.isTerminated else {
            return false
        }

        app.unhide()
        if #available(macOS 14.0, *) {
            if app.activate(options: [.activateAllWindows]) {
                return true
            }
        } else {
            if app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps]) {
                return true
            }
        }

        if app.activate(options: [.activateAllWindows]) {
            return true
        }
        return app.activate(options: [])
    }

    private func bestRunningApp(bundleID: String, preferredPID: pid_t) -> NSRunningApplication? {
        let candidates = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { !$0.isTerminated }

        guard !candidates.isEmpty else {
            return nil
        }

        return candidates.max { lhs, rhs in
            runningAppRank(lhs, preferredPID: preferredPID) < runningAppRank(rhs, preferredPID: preferredPID)
        }
    }

    private func runningAppRank(_ app: NSRunningApplication, preferredPID: pid_t) -> Int {
        activationRank(app, preferredPID: preferredPID)
    }

    private func visibleWindowCount(for pid: pid_t) -> Int {
        guard let infoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return 0
        }

        var count = 0
        let target = Int(pid)
        for info in infoList {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? Int, ownerPID == target else {
                continue
            }
            if let layer = info[kCGWindowLayer as String] as? Int, layer != 0 {
                continue
            }
            if let alpha = info[kCGWindowAlpha as String] as? Double, alpha <= 0 {
                continue
            }
            count += 1
        }

        return count
    }

    private func discoverRunningApps() -> [ListedAppEntry] {
        let running = NSWorkspace.shared.runningApplications.filter { app in
            guard !app.isTerminated else { return false }
            guard let bundleID = app.bundleIdentifier?.lowercased(), !bundleID.isEmpty else { return false }
            guard app.bundleIdentifier != Bundle.main.bundleIdentifier else { return false }
            guard app.localizedName != nil else { return false }

            let name = app.localizedName?.lowercased() ?? ""
            if excludedBundleIDs.contains(bundleID) { return false }
            if helperKeywords.contains(where: { bundleID.contains($0) || name.contains($0) }) { return false }

            // Regular apps are always listed.
            if app.activationPolicy == .regular {
                return true
            }

            // Accessory apps are listed only when they are usable:
            // either a visible window exists, or they match known tray-app keywords.
            if app.activationPolicy == .accessory {
                if visibleWindowCount(for: app.processIdentifier) > 0 {
                    return true
                }
                if accessoryAllowKeywords.contains(where: { bundleID.contains($0) || name.contains($0) }) {
                    return true
                }
            }

            return false
        }

        var bestByBundleID: [String: NSRunningApplication] = [:]
        for app in running {
            guard let bundleID = app.bundleIdentifier else {
                continue
            }

            if let current = bestByBundleID[bundleID] {
                if appScore(app) > appScore(current) {
                    bestByBundleID[bundleID] = app
                }
            } else {
                bestByBundleID[bundleID] = app
            }
        }

        let entries = bestByBundleID.compactMap { (bundleID, app) -> ListedAppEntry? in
            let name = app.localizedName ?? bundleID
            let iconCopy = app.icon?.copy() as? NSImage
            iconCopy?.size = NSSize(width: 16, height: 16)
            return ListedAppEntry(app: app, displayName: name, bundleID: bundleID, icon: iconCopy)
        }

        return entries
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            .prefix(maxMenuItems)
            .map { $0 }
    }

    private func appScore(_ app: NSRunningApplication) -> Int {
        var score = 0
        if app.activationPolicy == .regular { score += 100 }
        if !app.isHidden { score += 10 }
        if app.icon != nil { score += 5 }
        score += min(visibleWindowCount(for: app.processIdentifier), 5) * 30
        return score
    }

    private func removeDynamicMenuItems(from menu: NSMenu) {
        for item in menu.items.reversed() where item.tag == dynamicItemTag {
            menu.removeItem(item)
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
