import AppKit

@main
enum Mal2geulApp {
    static func main() {
        // Launched again while running: bring up the settings of the running copy instead.
        if isAlreadyRunning {
            DistributedNotificationCenter.default().postNotificationName(.showSettings, object: nil, userInfo: nil, deliverImmediately: true)
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // menu bar only, no Dock icon
        app.run()
    }

    private static var isAlreadyRunning: Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let current = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .contains { $0.processIdentifier != current }
    }
}

extension Notification.Name {
    static let showSettings = Notification.Name("app.mal2geul.mac.show-settings")
}
