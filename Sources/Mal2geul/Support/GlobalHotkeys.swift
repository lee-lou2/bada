import AppKit
import Carbon

/// System-wide shortcuts through Carbon. Unlike event taps, these need no Accessibility permission.
final class GlobalHotkeys {
    static let shared = GlobalHotkeys()

    enum Slot: UInt32 {
        case dictation = 1
        /// esc, held only while a dictation is running.
        case cancel = 2
    }

    private let signature: OSType = 0x4D32_474C // "M2GL"
    private var handler: EventHandlerRef?
    private var hotkeys: [UInt32: EventHotKeyRef] = [:]
    private var actions: [UInt32: () -> Void] = [:]

    private init() {}

    /// Returns false when macOS refuses the combination, usually because another app owns it.
    @discardableResult
    func register(_ slot: Slot, _ shortcut: Shortcut, action: @escaping () -> Void) -> Bool {
        installHandler()
        unregister(slot)
        var hotkey: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            EventHotKeyID(signature: signature, id: slot.rawValue),
            GetApplicationEventTarget(),
            0,
            &hotkey
        )
        guard status == noErr, let hotkey else {
            Log.info("hotkey \(shortcut.displayName) unavailable (\(status))")
            return false
        }
        hotkeys[slot.rawValue] = hotkey
        actions[slot.rawValue] = action
        return true
    }

    func unregister(_ slot: Slot) {
        if let hotkey = hotkeys.removeValue(forKey: slot.rawValue) {
            UnregisterEventHotKey(hotkey)
        }
        actions[slot.rawValue] = nil
    }

    func isRegistered(_ slot: Slot) -> Bool { hotkeys[slot.rawValue] != nil }

    private func installHandler() {
        guard handler == nil else { return }
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var id = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &id
            )
            guard status == noErr else { return status }
            DispatchQueue.main.async { GlobalHotkeys.shared.actions[id.id]?() }
            return noErr
        }, 1, &pressed, nil, &handler)
    }
}
