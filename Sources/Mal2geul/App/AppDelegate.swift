import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let preferences = Preferences.shared
    private let permissions = Permissions.shared
    private let engine = SpeechEngine()
    private let shortcutRecorder = ShortcutRecorder()
    private lazy var dictation = DictationController(engine: engine)
    private lazy var menuBar = MenuBar()
    private lazy var settings = SettingsWindow { [unowned self] in
        AnyView(
            SettingsView(
                preferences: preferences,
                engine: engine,
                permissions: permissions,
                shortcutRecorder: shortcutRecorder,
                microphones: MicrophoneList.shared
            )
        )
    }

    private var isShortcutAvailable = true
    private var subscriptions = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.info("launch \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "?")")
        MainMenu.install()
        engine.start()
        setUpMenuBar()
        setUpShortcut()

        dictation.onPhaseChange = { [weak self] in self?.refreshMenuBarIcon() }
        dictation.onNeedsSettings = { [weak self] in self?.settings.show() }
        engine.$status.receive(on: RunLoop.main).sink { [weak self] _ in self?.refreshMenuBarIcon() }.store(in: &subscriptions)
        DistributedNotificationCenter.default().addObserver(forName: .showSettings, object: nil, queue: .main) { [weak self] _ in
            self?.settings.show()
        }

        // First launch, or something still needs permission: open settings to guide the user.
        permissions.refresh()
        if !preferences.didLaunchBefore || !permissions.allGranted {
            preferences.didLaunchBefore = true
            settings.show()
            if permissions.microphone == .notDetermined { permissions.requestMicrophone() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settings.show()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        dictation.cancel()
        engine.stop()
        preferences.flush()
    }

    // MARK: Shortcut

    private func setUpShortcut() {
        shortcutRecorder.suspendShortcut = { GlobalHotkeys.shared.unregister(.dictation) }
        shortcutRecorder.applyShortcut = { [weak self] shortcut in self?.apply(shortcut) ?? false }
        settings.onClose = { [weak self] in self?.shortcutRecorder.cancel() }
        isShortcutAvailable = register(preferences.shortcut)
        if !isShortcutAvailable { shortcutRecorder.showUnavailable() }
    }

    private func register(_ shortcut: Shortcut) -> Bool {
        GlobalHotkeys.shared.register(.dictation, shortcut) { [weak self] in self?.dictation.toggle() }
    }

    /// Switches to `shortcut`, or re-registers the current one when nil. Keeps the old one if macOS refuses.
    private func apply(_ shortcut: Shortcut?) -> Bool {
        defer { refreshMenuBarIcon() }
        guard let shortcut, shortcut != preferences.shortcut || !GlobalHotkeys.shared.isRegistered(.dictation) else {
            isShortcutAvailable = register(preferences.shortcut)
            return isShortcutAvailable
        }
        if register(shortcut) {
            preferences.shortcut = shortcut
            isShortcutAvailable = true
            return true
        }
        isShortcutAvailable = register(preferences.shortcut)
        return false
    }

    // MARK: Menu bar

    private func setUpMenuBar() {
        menuBar.onToggleDictation = { [weak self] in self?.dictation.toggle() }
        menuBar.onOpenSettings = { [weak self] in self?.settings.show() }
        menuBar.onRestartEngine = { [weak self] in self?.engine.restart() }
        menuBar.currentState = { [weak self] in
            guard let self else { return nil }
            return MenuBar.State(
                phase: self.dictation.phase,
                engineStatus: self.engine.status,
                shortcut: self.isShortcutAvailable ? self.preferences.shortcut : nil
            )
        }
    }

    private func refreshMenuBarIcon() {
        menuBar.setActive(dictation.phase != .idle)
    }
}
