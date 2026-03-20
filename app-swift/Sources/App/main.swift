import AppKit
import CoreServices
import CoreGraphics
import ApplicationServices

private struct ListedAppEntry {
	let displayApp: NSRunningApplication
	let activationApp: NSRunningApplication

	var displayName: String {
		displayApp.localizedName ?? displayApp.bundleIdentifier ?? "Unknown App"
	}
}

final class AppActivationTarget: NSObject {
	let activationPID: pid_t
	let activationBundleIdentifier: String?
	let activationBundleURL: URL?
	let activationDisplayName: String
	let displayName: String

	init(displayApp: NSRunningApplication, activationApp: NSRunningApplication) {
		self.activationPID = activationApp.processIdentifier
		self.activationBundleIdentifier = activationApp.bundleIdentifier
		self.activationBundleURL = activationApp.bundleURL
		self.activationDisplayName = activationApp.localizedName ?? activationApp.bundleIdentifier ?? ""
		self.displayName = displayApp.localizedName ?? displayApp.bundleIdentifier ?? "Unknown App"
	}
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
	private var statusItem: NSStatusItem?
	private let dynamicItemTag = 9001
	private let emptyItemTag = 9002
	private let helperKeywords = ["helper", "daemon", "agent", "plugin", "service", "renderer", "gpu", "crashpad"]
	private let subAppKeywords = ["小程序", "miniapp", "mini app"]
	private let excludedBundleSubstrings = [
		"com.tencent.flue.weapp",
		"com.tencent.flue.helper",
		"com.apple.appkit.xpc.openandsavepanelservice",
		"com.apple.quicklook.quicklookuiservice",
		"com.apple.safariplatformsupport.helper",
		"com.microsoft.sharepoint-mac"
	]
	private let excludedBundlePrefixes = ["com.apple."]
	private let excludedBundleIdentifiers = Set([
		"com.apple.finder",
		"com.apple.controlcenter",
		"com.apple.systemuiserver",
		"com.apple.notificationcenterui"
	])
	private let maxMenuItems = 40

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

		let entries = discoverMenuBarCandidateApps()

		if entries.isEmpty {
			menu.item(withTag: emptyItemTag)?.isHidden = false
			return
		}

		menu.item(withTag: emptyItemTag)?.isHidden = true
		let anchorIndex = 0
		let nameCounts = Dictionary(grouping: entries, by: { $0.displayName })
		var nameOffsets: [String: Int] = [:]

		for (offset, entry) in entries.enumerated() {
			let baseName = entry.displayName
			let total = nameCounts[baseName]?.count ?? 1
			let current = (nameOffsets[baseName] ?? 0) + 1
			nameOffsets[baseName] = current
			let name = total > 1 ? "\(baseName) (\(current))" : baseName
			let listItem = NSMenuItem(title: name, action: #selector(activateListedApp(_:)), keyEquivalent: "")
			listItem.tag = dynamicItemTag
			listItem.target = self
			listItem.representedObject = AppActivationTarget(displayApp: entry.displayApp, activationApp: entry.activationApp)
			if let icon = entry.displayApp.icon {
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

		let family = appFamily(bundleID: targetInfo.activationBundleIdentifier, appName: targetInfo.activationDisplayName)

		if activateRunningApp(pid: targetInfo.activationPID) {
			_ = forceAggressiveFrontmost(pid: targetInfo.activationPID)
			_ = focusWindowViaAccessibility(pid: targetInfo.activationPID)
			_ = raiseFrontWindowIfNeeded(pid: targetInfo.activationPID)
			if let bundleID = targetInfo.activationBundleIdentifier {
				if shouldReopenForFamily(family) {
					_ = reopenByAppleScript(bundleIdentifier: bundleID)
				}
				_ = activateByAppleScript(bundleIdentifier: bundleID)
				_ = activateByWorkspace(bundleIdentifier: bundleID)
				_ = forceAggressiveFrontmost(pid: targetInfo.activationPID)
				_ = focusWindowViaAccessibility(pid: targetInfo.activationPID)
				_ = raiseFrontWindowIfNeeded(pid: targetInfo.activationPID)
				if family == .onedrive {
					_ = reopenByAppleScript(bundleIdentifier: bundleID)
				}
			}
			if !targetInfo.activationDisplayName.isEmpty {
				_ = activateByAppleScript(appName: targetInfo.activationDisplayName)
				if family == .onedrive {
					_ = activateByAppleScript(appName: "OneDrive")
				}
			}
			_ = activateFamilyFallback(family: family, bundleIdentifier: targetInfo.activationBundleIdentifier, appName: targetInfo.activationDisplayName)
			return
		}

		if let bundleID = targetInfo.activationBundleIdentifier,
		   activateByBundleIdentifier(bundleID, preferredPID: targetInfo.activationPID),
		   let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
			.filter({ !$0.isTerminated })
			.max(by: { score(for: $0) < score(for: $1) }) {
			_ = focusWindowViaAccessibility(pid: app.processIdentifier)
			_ = raiseFrontWindowIfNeeded(pid: app.processIdentifier)
			if !targetInfo.activationDisplayName.isEmpty {
				_ = activateByAppleScript(appName: targetInfo.activationDisplayName)
			}
			_ = activateFamilyFallback(family: family, bundleIdentifier: targetInfo.activationBundleIdentifier, appName: targetInfo.activationDisplayName)
			return
		}

		if let bundleURL = targetInfo.activationBundleURL {
			let configuration = NSWorkspace.OpenConfiguration()
			configuration.activates = true
			NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration) { _, _ in }
			_ = activateFamilyFallback(family: family, bundleIdentifier: targetInfo.activationBundleIdentifier, appName: targetInfo.activationDisplayName)
			return
		}

		// If no running target can be activated, refresh list and avoid launching stale/non-running entries.
		refreshMenuBarAppList()
	}

	private func activateFamilyFallback(family: AppFamily, bundleIdentifier: String?, appName: String?) -> Bool {
		var changed = false

		if let bundleIdentifier {
			let instances = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
				.filter { !$0.isTerminated }
				.sorted { score(for: $0) > score(for: $1) }

			for app in instances {
				if activateRunningApp(app: app) {
					changed = true
				}
				if forceAggressiveFrontmost(pid: app.processIdentifier) {
					changed = true
				}
				if focusWindowViaAccessibility(pid: app.processIdentifier) {
					changed = true
				}
			}

			switch family {
			case .wechat, .v2ray, .quark, .uu:
				if reopenByAppleScript(bundleIdentifier: bundleIdentifier) {
					changed = true
				}
			default:
				break
			}

			if activateByAppleScript(bundleIdentifier: bundleIdentifier) {
				changed = true
			}
		}

		if let appName, !appName.isEmpty {
			switch family {
			case .wechat, .v2ray, .quark, .uu:
				if reopenByAppleScript(appName: appName) {
					changed = true
				}
			default:
				break
			}

			if activateByAppleScript(appName: appName) {
				changed = true
			}
		}

		return changed
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
		let family = appFamily(bundleID: bundleID, appName: runningInstances.first?.localizedName)

		if let best = pickBestRunningInstance(bundleIdentifier: bundleID, preferredPID: preferredPID),
		   activateRunningApp(app: best) {
			_ = forceAggressiveFrontmost(pid: best.processIdentifier)
			_ = focusWindowViaAccessibility(pid: best.processIdentifier)
			_ = forceFrontmostIfNeeded(pid: best.processIdentifier)
			if shouldReopenForFamily(family) {
				_ = reopenByAppleScript(bundleIdentifier: bundleID)
			}
			_ = activateByAppleScript(bundleIdentifier: bundleID)
			_ = activateByWorkspace(bundleIdentifier: bundleID)
			return true
		}

		if !runningInstances.isEmpty {
			return activateByAppleScript(bundleIdentifier: bundleID)
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

	private func activateByAppleScript(bundleIdentifier: String) -> Bool {
		var errorInfo: NSDictionary?
		let script = NSAppleScript(source: "tell application id \"\(bundleIdentifier)\" to activate")
		_ = script?.executeAndReturnError(&errorInfo)
		return errorInfo == nil
	}

	private func reopenByAppleScript(bundleIdentifier: String) -> Bool {
		var errorInfo: NSDictionary?
		let script = NSAppleScript(source: "tell application id \"\(bundleIdentifier)\" to reopen")
		_ = script?.executeAndReturnError(&errorInfo)
		return errorInfo == nil
	}

	private func reopenByAppleScript(appName: String) -> Bool {
		var errorInfo: NSDictionary?
		let script = NSAppleScript(source: "tell application \"\(appName)\" to reopen")
		_ = script?.executeAndReturnError(&errorInfo)
		return errorInfo == nil
	}

	private func activateByAppleScript(appName: String) -> Bool {
		var errorInfo: NSDictionary?
		let script = NSAppleScript(source: "tell application \"\(appName)\" to activate")
		_ = script?.executeAndReturnError(&errorInfo)
		return errorInfo == nil
	}

	private func activateByWorkspace(bundleIdentifier: String) -> Bool {
		guard let url = appURLForBundleIdentifier(bundleIdentifier) else {
			return false
		}

		let configuration = NSWorkspace.OpenConfiguration()
		configuration.activates = true
		NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in }
		return true
	}

	private func raiseFrontWindowIfNeeded(pid: pid_t) -> Bool {
		var errorInfo: NSDictionary?
		let script = NSAppleScript(source: "tell application \"System Events\"\n  tell (first process whose unix id is \(pid))\n    if (count of windows) > 0 then\n      try\n        perform action \"AXRaise\" of window 1\n      end try\n    end if\n    set frontmost to true\n  end tell\nend tell")
		_ = script?.executeAndReturnError(&errorInfo)
		return errorInfo == nil
	}

	private func forceAggressiveFrontmost(pid: pid_t) -> Bool {
		guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else {
			return false
		}

		app.unhide()
		if app.activate(options: [.activateIgnoringOtherApps, .activateAllWindows]) {
			return true
		}

		return app.activate(options: [.activateIgnoringOtherApps])
	}

	private func focusWindowViaAccessibility(pid: pid_t) -> Bool {
		let appElement = AXUIElementCreateApplication(pid)
		var ok = false

		let frontSet = AXUIElementSetAttributeValue(
			appElement,
			kAXFrontmostAttribute as CFString,
			kCFBooleanTrue
		)

		if frontSet == .success {
			ok = true
		}

		var focusedWindow: CFTypeRef?
		let focusedResult = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindow)
		if focusedResult == .success, let focusedWindow {
			let windowElement = focusedWindow as! AXUIElement
			if AXUIElementPerformAction(windowElement, kAXRaiseAction as CFString) == .success {
				ok = true
			}
		}

		return ok
	}

	private func forceFrontmostIfNeeded(pid: pid_t) -> Bool {
		var errorInfo: NSDictionary?
		let script = NSAppleScript(source: "tell application \"System Events\"\n  tell (first process whose unix id is \(pid))\n    set frontmost to true\n  end tell\nend tell")
		_ = script?.executeAndReturnError(&errorInfo)
		return errorInfo == nil
	}

	private func appURLForBundleIdentifier(_ bundleID: String) -> URL? {
		guard let unmanaged = LSCopyApplicationURLsForBundleIdentifier(bundleID as CFString, nil),
		      let urls = unmanaged.takeRetainedValue() as? [URL],
		      let first = urls.first else {
			return nil
		}

		return first
	}

	private func removeDynamicAppItems(from menu: NSMenu) {
		for item in menu.items.reversed() where item.tag == dynamicItemTag {
			menu.removeItem(item)
		}
	}

	private func discoverMenuBarCandidateApps() -> [ListedAppEntry] {
		let candidates = NSWorkspace.shared.runningApplications
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

				if excludedBundleSubstrings.contains(where: { bundleID.contains($0) }) {
					return false
				}

				if helperKeywords.contains(where: { bundleID.contains($0) || appName.contains($0) }) {
					return false
				}

				if subAppKeywords.contains(where: { appName.contains($0) }) {
					return false
				}

				// Keep prohibited as fallback because some menu bar apps use it but are user-visible.
				return app.activationPolicy == .regular || app.activationPolicy == .accessory || app.activationPolicy == .prohibited
			}

		var mergedGroups: [String: [NSRunningApplication]] = [:]
		var entries: [ListedAppEntry] = []

		for app in candidates {
			if let key = mergeGroupKey(for: app) {
				mergedGroups[key, default: []].append(app)
			} else {
				entries.append(ListedAppEntry(displayApp: app, activationApp: app))
			}
		}

		for (key, groupApps) in mergedGroups {
			guard let activation = bestActivationApp(in: groupApps, groupKey: key) else {
				continue
			}
			guard let display = bestDisplayApp(in: groupApps, groupKey: key) else {
				continue
			}
			entries.append(ListedAppEntry(displayApp: display, activationApp: activation))
		}

		entries.sort { lhs, rhs in
			if lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedSame {
				return lhs.activationApp.processIdentifier < rhs.activationApp.processIdentifier
			}
			return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
		}

		return Array(entries.prefix(maxMenuItems))
	}

	private func mergeGroupKey(for app: NSRunningApplication) -> String? {
		let bundleID = app.bundleIdentifier?.lowercased() ?? ""
		let appName = app.localizedName?.lowercased() ?? ""

		if bundleID.contains("wechat") || bundleID.contains("tencent") || appName.contains("微信") || appName.contains("wechat") {
			return "wechat"
		}

		if bundleID.contains("quark") || appName.contains("夸克") || appName.contains("quark") {
			return "quark"
		}

		if bundleID.contains("uu") || appName.contains("uu") {
			return "uu"
		}

		if bundleID.contains("v2ray") || appName.contains("v2ray") {
			return "v2ray"
		}

		return nil
	}

	private enum AppFamily {
		case wechat
		case quark
		case uu
		case v2ray
		case onedrive
		case other
	}

	private func appFamily(bundleID: String?, appName: String?) -> AppFamily {
		let bundle = bundleID?.lowercased() ?? ""
		let name = appName?.lowercased() ?? ""

		if bundle.contains("wechat") || bundle.contains("tencent") || name.contains("微信") || name.contains("wechat") {
			return .wechat
		}

		if bundle.contains("quark") || name.contains("夸克") || name.contains("quark") {
			return .quark
		}

		if bundle.contains("uu") || name.contains("uu") {
			return .uu
		}

		if bundle.contains("v2ray") || name.contains("v2ray") {
			return .v2ray
		}

		if bundle.contains("onedrive") || name.contains("onedrive") {
			return .onedrive
		}

		return .other
	}

	private func shouldReopenForFamily(_ family: AppFamily) -> Bool {
		switch family {
		case .wechat, .quark, .uu, .v2ray:
			return true
		case .onedrive, .other:
			return false
		}
	}

	private func displayScore(for app: NSRunningApplication) -> Int {
		var value = score(for: app)
		if app.icon != nil {
			value += 80
		}
		if app.activationPolicy == .regular {
			value += 40
		}
		return value
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

		if bundleID == "com.tencent.xinwechat" {
			score += 1200
		}

		if bundleID.contains("com.tencent.flue.wechatappex") {
			score -= 900
		}

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

	private func bestActivationApp(in apps: [NSRunningApplication], groupKey: String) -> NSRunningApplication? {
		if groupKey == "wechat" {
			if let main = apps.first(where: { ($0.bundleIdentifier ?? "").lowercased() == "com.tencent.xinwechat" && !$0.isTerminated }) {
				return main
			}
		}

		return apps.filter { !$0.isTerminated }.max(by: { score(for: $0) < score(for: $1) })
	}

	private func bestDisplayApp(in apps: [NSRunningApplication], groupKey: String) -> NSRunningApplication? {
		if groupKey == "wechat" {
			if let main = apps.first(where: { ($0.bundleIdentifier ?? "").lowercased() == "com.tencent.xinwechat" && !$0.isTerminated }) {
				return main
			}
		}

		return apps.filter { !$0.isTerminated }.max(by: { displayScore(for: $0) < displayScore(for: $1) })
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
