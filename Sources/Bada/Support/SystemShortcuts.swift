import AppKit
import Carbon

/// macOS's own keyboard shortcuts (System Settings › Keyboard › Keyboard Shortcuts).
/// When one uses the same keys, macOS may take the key press before bada sees it.
enum SystemShortcuts {
    private static let names: [Int: String] = [
        32: "Mission Control",
        33: "응용 프로그램 윈도우",
        36: "데스크탑 보기",
        60: "이전 입력 소스 선택",
        61: "입력 메뉴에서 다음 소스 선택",
        64: "Spotlight 검색",
        65: "Finder 검색 윈도우",
        163: "알림 센터",
        175: "받아쓰기",
        184: "스크린샷 및 기록 옵션",
    ]

    /// Name of an enabled system shortcut that uses the same keys, if any.
    static func conflict(with shortcut: Shortcut) -> String? {
        guard let table = UserDefaults(suiteName: "com.apple.symbolichotkeys")?
            .dictionary(forKey: "AppleSymbolicHotKeys") else { return nil }
        let wanted = cocoaModifiers(shortcut.modifiers)
        for (id, raw) in table {
            guard let entry = raw as? [String: Any],
                  (entry["enabled"] as? Bool) ?? false,
                  let value = entry["value"] as? [String: Any],
                  let parameters = value["parameters"] as? [Int], parameters.count >= 3 else { continue }
            let keyCode = parameters[1]
            let modifiers = parameters[2] & 0x1E0000 // ⇧⌃⌥⌘ only
            if keyCode == Int(shortcut.keyCode), modifiers == wanted {
                return names[Int(id) ?? -1] ?? "macOS 단축키"
            }
        }
        return nil
    }

    static func openSettings() {
        let links = [
            "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Shortcuts",
            "x-apple.systempreferences:com.apple.preference.keyboard?Shortcuts",
        ]
        for link in links {
            if let url = URL(string: link), NSWorkspace.shared.open(url) { return }
        }
    }

    private static func cocoaModifiers(_ carbon: UInt32) -> Int {
        var mask = 0
        if carbon & UInt32(shiftKey) != 0 { mask |= 0x20000 }
        if carbon & UInt32(controlKey) != 0 { mask |= 0x40000 }
        if carbon & UInt32(optionKey) != 0 { mask |= 0x80000 }
        if carbon & UInt32(cmdKey) != 0 { mask |= 0x100000 }
        return mask
    }
}
