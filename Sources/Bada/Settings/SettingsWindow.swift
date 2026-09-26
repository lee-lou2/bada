import AppKit
import SwiftUI

/// The settings window. A normal window: other windows can cover it.
final class SettingsWindow: NSObject, NSWindowDelegate {
    var onClose: (() -> Void)?

    private let makeContent: () -> AnyView
    private var window: NSWindow?

    init(content: @escaping () -> AnyView) {
        makeContent = content
    }

    func show() {
        let window = self.window ?? makeWindow()
        Permissions.shared.watch(true)
        MicrophoneList.shared.refresh()
        if !window.isVisible {
            if let view = window.contentViewController?.view {
                view.layoutSubtreeIfNeeded()
                window.setContentSize(view.fittingSize)
            }
            window.center()
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        window.makeFirstResponder(nil)
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
        Permissions.shared.watch(false)
        Preferences.shared.flush()
    }

    private func makeWindow() -> NSWindow {
        let controller = NSHostingController(rootView: makeContent())
        controller.sizingOptions = [.preferredContentSize]
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: SettingsView.width, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "bada 설정"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenNone]
        window.contentViewController = controller
        window.delegate = self
        window.setFrameAutosaveName("Settings")
        self.window = window
        return window
    }
}
