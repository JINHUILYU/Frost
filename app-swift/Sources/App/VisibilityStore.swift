import Foundation

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

    func reset() {
        defaults.removeObject(forKey: hiddenBundleDefaultsKey)
    }
}
