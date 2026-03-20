import AppKit
import CoreServices
import CoreGraphics

final class AppActivationTarget: NSObject {
	let pid: pid_t
	let bundleIdentifier: String?
	let bundleURL: URL?
	let displayName: String

	init(app: NSRunningApplication) {
		self.pid = app.processIdentifier
		self.bundleIdentifier = app.bundleIdentifier
		self.bundleURL = app.bundleURL
		self.displayName = app.localizedName ?? app.bundleIdentifier ?? "Unknown App"
	}
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
	private var statusItem: NSStatusItem?
	private let dynamicItemTag = 9001
	private let emptyItemTag = 9002
	private let helperKeywords = ["helper", "daemon", "agent", "plugin", "service", "renderer", "gpu", "crashpad"]
	private let subAppKeywords = ["小程序", "miniapp", "mini app"]
	private let excludedBundlePrefixes = ["com.apple."]
	private let excludedBundleIdentifiers = Set([
		"com.apple.finder",
		"com.apple.controlcenter",
		"com.apple.systemuiserver",
		"com.apple.notificationcenterui"
	])
	private let maxMenuItems = 30

	func applicationDidFinishLaunching(_ notification: Notification) {
		let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
		item.button?.title = "FrostBar"

		let menu = NSMenu()
		menu.delegate = self

		let empty = NSMenuItem(title: "No candidate apps", action: nil, keyEquivalent: "")
		empty.tag = emptyItemTag
		empty.isHidden = true
		menu.addItem(empty)

		menu.addItem(NSMenuItem.separator())
		menu.addItem(
			withTitle: "Quit FrostBar",
			action: #selector(quitApp),
			keyEquivalent: "q"
		)
		menu.items.last?.target = self
		item.menu = menu

		self.statusItem = item
		refreshMenuBarAppList()
	}

	func menuWillOpen(_ menu: NSMenu) {
		refreshMenuBarAppList()
	}

	@objc private func refreshMenuBarAppList() {
		guard let menu = statusItem?.menu else {
			return
		}

		removeDynamicAppItems(from: menu)

		let apps = discoverMenuBarCandidateApps()

		if apps.isEmpty {
			menu.item(withTag: emptyItemTag)?.isHidden = false
			return
		}

		menu.item(withTag: emptyItemTag)?.isHidden = true
		let anchorIndex = 0

		for (offset, app) in apps.enumerated() {
			let name = app.localizedName ?? app.bundleIdentifier ?? "Unknown App"
			let listItem = NSMenuItem(title: name, action: #selector(activateListedApp(_:)), keyEquivalent: "")
			listItem.tag = dynamicItemTag
			listItem.target = self
			listItem.representedObject = AppActivationTarget(app: app)
			if let icon = app.icon {
				let sizedIcon = icon.copy() as? NSImage ?? icon
				sizedIcon.size = NSSize(width: 16, height: 16)
				listItem.image = sizedIcon
			}
			menu.insertItem(listItem, at: anchorIndex + offset)
		}
	}

	@objc private func activateListedApp(_ sender: NSMenuItem) {
		guard let targetInfo = sender.representedObject as? AppActivationTarget else {
			return
		}

		if let bundleID = targetInfo.bundleIdentifier,
		   let best = pickBestRunningInstance(bundleIdentifier: bundleID, preferredPID: targetInfo.pid),
		   activateRunningApp(app: best) {
			_ = forceFrontmostIfNeeded(pid: best.processIdentifier)
			return
		}

		if activateRunningApp(pid: targetInfo.pid) {
			return
		}

		if let bundleID = targetInfo.bundleIdentifier, activateByBundleIdentifier(bundleID, preferredPID: targetInfo.pid) {
			return
		}

		if let bundleURL = targetInfo.bundleURL {
			let config = NSWorkspace.OpenConfiguration()
			config.activates = true
			NSWorkspace.shared.openApplication(at: bundleURL, configuration: config) { _, _ in }
			return
		}
	}

	private func activateRunningApp(pid: pid_t) -> Bool {
		guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else {
			return false
		}

		return activateRunningApp(app: app)
	}

	private func activateRunningApp(app: NSRunningApplication) -> Bool {
		if app.isTerminated {
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

		return app.activate(options: [])
	}

	private func activateByBundleIdentifier(_ bundleID: String, preferredPID: pid_t?) -> Bool {
		let runningInstances = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
			.filter { !$0.isTerminated }

		if let best = pickBestRunningInstance(bundleIdentifier: bundleID, preferredPID: preferredPID),
		   activateRunningApp(app: best) {
			_ = forceFrontmostIfNeeded(pid: best.processIdentifier)
			return true
		}

		// Do not open new app instances if this bundle is already running.
		if !runningInstances.isEmpty {
			return false
		}

		if let appURL = appURLForBundleIdentifier(bundleID) {
			let config = NSWorkspace.OpenConfiguration()
			config.activates = true
			NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, _ in }
			return true
		}

		return false
	}

	private func pickBestRunningInstance(bundleIdentifier: String, preferredPID: pid_t?) -> NSRunningApplication? {
		let candidates = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
			.filter { !$0.isTerminated }

		if let preferredPID, let preferred = candidates.first(where: { $0.processIdentifier == preferredPID }) {
			return preferred
		}

		return candidates.max { lhs, rhs in
			score(for: lhs) < score(for: rhs)
		}
	}

	private func appURLForBundleIdentifier(_ bundleID: String) -> URL? {
		guard let unmanaged = LSCopyApplicationURLsForBundleIdentifier(bundleID as CFString, nil),
		      let urls = unmanaged.takeRetainedValue() as? [URL] else {
			return nil
		}

		return urls.first
	}

	private func forceFrontmostIfNeeded(pid: pid_t) -> Bool {
		var errorInfo: NSDictionary?
		let script = NSAppleScript(source: "tell application \"System Events\"\n  tell (first process whose unix id is \(pid))\n    set frontmost to true\n  end tell\nend tell")
		_ = script?.executeAndReturnError(&errorInfo)
		return errorInfo == nil
	}

	private func removeDynamicAppItems(from menu: NSMenu) {
		for item in menu.items.reversed() where item.tag == dynamicItemTag {
			menu.removeItem(item)
		}
	}

	private func discoverMenuBarCandidateApps() -> [NSRunningApplication] {
		let grouped = Dictionary(grouping: NSWorkspace.shared.runningApplications) { app -> String in
			if let bundleID = app.bundleIdentifier, !bundleID.isEmpty {
				return canonicalGroupKey(bundleID: bundleID, appName: app.localizedName)
			}
			let name = app.localizedName ?? ""
			return canonicalGroupKey(bundleID: nil, appName: name)
		}

		let apps = grouped.values
			.compactMap { pickBestActivationTarget(from: $0) }
			.filter { app in
				if app.bundleIdentifier == Bundle.main.bundleIdentifier {
					return false
				}

				if app.isTerminated {
					return false
				}

				if app.bundleIdentifier == nil || app.localizedName == nil {
					return false
				}

				let bundleID = app.bundleIdentifier?.lowercased() ?? ""
				let appName = app.localizedName?.lowercased() ?? ""

				if excludedBundleIdentifiers.contains(bundleID) {
					return false
				}

				if excludedBundlePrefixes.contains(where: { bundleID.hasPrefix($0) }) {
					return false
				}

				if helperKeywords.contains(where: { bundleID.contains($0) || appName.contains($0) }) {
					return false
				}

				if subAppKeywords.contains(where: { appName.contains($0) }) {
					return false
				}

				if isInteractiveFamily(bundleID: bundleID, appName: appName), app.activationPolicy != .regular {
					return false
				}

				// Keep prohibited as fallback because some menu bar apps use it but are user-visible.
				return app.activationPolicy == .regular || app.activationPolicy == .accessory || app.activationPolicy == .prohibited
			}
			.sorted { lhs, rhs in
				let left = lhs.localizedName ?? lhs.bundleIdentifier ?? ""
				let right = rhs.localizedName ?? rhs.bundleIdentifier ?? ""
				return left.localizedCaseInsensitiveCompare(right) == .orderedAscending
			}

		return Array(apps.prefix(maxMenuItems))
	}

	private func pickBestActivationTarget(from apps: [NSRunningApplication]) -> NSRunningApplication? {
		let candidates = apps.filter { !$0.isTerminated }
		if candidates.isEmpty {
			return nil
		}

		return candidates.max { lhs, rhs in
			score(for: lhs) < score(for: rhs)
		}
	}

	private func score(for app: NSRunningApplication) -> Int {
		var score = 0

		switch app.activationPolicy {
		case .regular:
			score += 200
		case .accessory:
			score += 80
		case .prohibited:
			score -= 300
		@unknown default:
			score -= 100
		}

		let bundleID = app.bundleIdentifier?.lowercased() ?? ""
		let name = app.localizedName?.lowercased() ?? ""
		let bundlePath = app.bundleURL?.path.lowercased() ?? ""

		if helperKeywords.contains(where: { bundleID.contains($0) || name.contains($0) || bundlePath.contains($0) }) {
			score -= 150
		}

		if bundlePath.hasSuffix(".app") {
			score += 30
		}

		if app.isHidden {
			score += 10
		}

		let windowCount = frontWindowCount(for: app.processIdentifier)
		if windowCount > 0 {
			score += 500
		}

		score += min(windowCount, 5) * 20

		return score
	}

	private func canonicalGroupKey(bundleID: String?, appName: String?) -> String {
		let bundle = bundleID?.lowercased() ?? ""
		let name = (appName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

		if isWeChat(bundleID: bundle, appName: name) {
			return "wechat-main"
		}

		if bundle.contains("quark") || name.contains("夸克") || name.contains("quark") {
			return "quark-main"
		}

		if bundle.contains("uu") || name.contains("uu") {
			return "uu-main"
		}

		if !bundle.isEmpty {
			return bundle
		}

		return name
	}

	private func isWeChat(bundleID: String, appName: String) -> Bool {
		return bundleID.contains("wechat") || bundleID.contains("tencent") || appName.contains("微信") || appName.contains("wechat")
	}

	private func isInteractiveFamily(bundleID: String, appName: String) -> Bool {
		if isWeChat(bundleID: bundleID, appName: appName) {
			return true
		}

		if bundleID.contains("quark") || appName.contains("夸克") || appName.contains("quark") {
			return true
		}

		if bundleID.contains("uu") || appName.contains("uu") {
			return true
		}

		if bundleID.contains("onedrive") || appName.contains("onedrive") {
			return true
		}

		return false
	}

	private func frontWindowCount(for pid: pid_t) -> Int {
		guard let infoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
			return 0
		}

		let targetPid = Int(pid)
		var count = 0

		for info in infoList {
			guard let ownerPid = info[kCGWindowOwnerPID as String] as? Int, ownerPid == targetPid else {
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

	@objc private func quitApp() {
		NSApp.terminate(nil)
	}
}

let app = NSApplication.shared
let delegate = AppDelegate()

app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
