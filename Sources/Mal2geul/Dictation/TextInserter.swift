import AppKit

/// Puts text on the clipboard and pastes it where the user was typing.
enum TextInserter {
    /// Returns false when macOS doesn't allow synthetic key presses yet (no Accessibility
    /// permission). The text is on the clipboard either way.
    @discardableResult
    static func insert(_ text: String, into field: FocusedField?) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        guard AXIsProcessTrusted() else { return false }

        // If the user switched apps while talking, go back to where the caret was.
        if let app = field?.app, !app.isTerminated, !app.isActive,
           app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            app.activate()
            whenActive(app, attempts: 12) { whenModifiersReleased(attempts: 40, then: pressPaste) }
        } else {
            whenModifiersReleased(attempts: 40, then: pressPaste)
        }
        return true
    }

    private static func pressPaste() {
        let source = CGEventSource(stateID: .hidSystemState)
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: KeyNames.pasteKeyCode, keyDown: isDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }

    /// Modifiers still held from the dictation shortcut would turn ⌘V into ⌃⌥⌘V.
    private static func whenModifiersReleased(attempts: Int, then action: @escaping () -> Void) {
        let held = CGEventSource.flagsState(.hidSystemState)
            .intersection([.maskControl, .maskAlternate, .maskCommand, .maskShift])
        guard !held.isEmpty, attempts > 0 else { return action() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            whenModifiersReleased(attempts: attempts - 1, then: action)
        }
    }

    private static func whenActive(_ app: NSRunningApplication, attempts: Int, then action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard app.isActive || attempts <= 0 else { return whenActive(app, attempts: attempts - 1, then: action) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: action)
        }
    }
}
