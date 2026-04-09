import Foundation

@discardableResult
func assert(_ condition: @autoclosure () -> Bool, _ message: String) -> Bool {
    if condition() {
        print("PASS: \(message)")
        return true
    }
    fputs("FAIL: \(message)\n", stderr)
    exit(1)
}

@main
struct VisibilityStoreTests {
    static func main() {
        let suiteName = "Frost.VisibilityStoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fputs("FAIL: cannot create UserDefaults suite\n", stderr)
            exit(1)
        }

        defaults.removePersistentDomain(forName: suiteName)
        let store = VisibilityStore(defaults: defaults)

        assert(store.hiddenBundleIDs().isEmpty, "initial hidden set is empty")
        assert(store.isVisible(bundleID: "com.apple.Safari"), "app visible by default")

        store.setVisible(false, for: "com.apple.Safari")
        assert(store.hiddenBundleIDs().contains("com.apple.Safari"), "hiding app persists hidden bundle id")
        assert(!store.isVisible(bundleID: "com.apple.Safari"), "hidden app reports invisible")

        store.setVisible(true, for: "com.apple.Safari")
        assert(!store.hiddenBundleIDs().contains("com.apple.Safari"), "showing app removes hidden bundle id")

        store.setVisible(false, for: "com.apple.Mail")
        store.reset()
        assert(store.hiddenBundleIDs().isEmpty, "reset clears hidden set")

        print("All VisibilityStore tests passed")
    }
}
