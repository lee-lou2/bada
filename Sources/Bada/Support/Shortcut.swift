import AppKit
import Carbon

/// A key plus modifiers, stored with Carbon's modifier mask so it can be registered directly.
struct Shortcut: Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    /// ⌃⌥Space
    static let standard = Shortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey))
    static let escape = Shortcut(keyCode: UInt32(kVK_Escape), modifiers: 0)

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init(event: NSEvent) {
        keyCode = UInt32(event.keyCode)
        modifiers = Shortcut.carbonModifiers(event.modifierFlags)
    }

    /// Needs ⌃, ⌥ or ⌘, except function keys, which work alone.
    var isValid: Bool {
        modifiers & UInt32(cmdKey | optionKey | controlKey) != 0 || KeyNames.isFunctionKey(keyCode)
    }

    var modifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        return flags
    }

    /// Keycaps in macOS order: ⌃ ⌥ ⇧ ⌘ key.
    var keys: [String] { Shortcut.symbols(modifierFlags) + [KeyNames.name(keyCode)] }

    var displayName: String { keys.joined() }

    /// Key equivalent for showing the shortcut next to a menu item.
    var menuKeyEquivalent: (key: String, flags: NSEvent.ModifierFlags)? {
        switch Int(keyCode) {
        case kVK_Space: return (" ", modifierFlags)
        case kVK_Return: return ("\r", modifierFlags)
        default:
            guard let character = KeyNames.character(keyCode)?.lowercased(), character.count == 1 else { return nil }
            return (character, modifierFlags)
        }
    }

    static func symbols(_ flags: NSEvent.ModifierFlags) -> [String] {
        var symbols: [String] = []
        if flags.contains(.control) { symbols.append("⌃") }
        if flags.contains(.option) { symbols.append("⌥") }
        if flags.contains(.shift) { symbols.append("⇧") }
        if flags.contains(.command) { symbols.append("⌘") }
        return symbols
    }

    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var mask: UInt32 = 0
        if flags.contains(.control) { mask |= UInt32(controlKey) }
        if flags.contains(.option) { mask |= UInt32(optionKey) }
        if flags.contains(.shift) { mask |= UInt32(shiftKey) }
        if flags.contains(.command) { mask |= UInt32(cmdKey) }
        return mask
    }
}

enum KeyNames {
    private static let special: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦", kVK_Escape: "esc", kVK_LeftArrow: "←",
        kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_ANSI_KeypadEnter: "⌤",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
        kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
        kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13", kVK_F14: "F14",
        kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18",
        kVK_F19: "F19", kVK_F20: "F20",
    ]

    static func isFunctionKey(_ code: UInt32) -> Bool {
        special[Int(code)]?.hasPrefix("F") ?? false
    }

    static func name(_ code: UInt32) -> String {
        special[Int(code)] ?? character(code)?.uppercased() ?? "#\(code)"
    }

    /// What the key types on the ASCII-capable layout, so a Korean input source still shows Latin keys.
    static func character(_ code: UInt32, modifiers: UInt32 = 0) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        return data.withUnsafeBytes { raw -> String? in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            var deadKeys: UInt32 = 0
            var length = 0
            var characters = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(
                layout, UInt16(code), UInt16(kUCKeyActionDisplay), (modifiers >> 8) & 0xFF,
                UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeys, characters.count, &length, &characters
            )
            guard status == noErr, length > 0 else { return nil }
            let text = String(utf16CodeUnits: characters, count: length)
            return text.trimmingCharacters(in: .controlCharacters).isEmpty ? nil : text
        }
    }

    /// The key that types "v" while ⌘ is held, so pasting works on any keyboard layout.
    static let pasteKeyCode: CGKeyCode = {
        for code in 0..<128 where character(UInt32(code), modifiers: UInt32(cmdKey))?.lowercased() == "v" {
            return CGKeyCode(code)
        }
        return CGKeyCode(kVK_ANSI_V)
    }()
}
