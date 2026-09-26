import AppKit

/// The menu bar icon and its menu. The menu is rebuilt every time it opens.
final class MenuBar: NSObject, NSMenuDelegate {
    struct State {
        var phase: DictationController.Phase
        var engineStatus: SpeechEngine.Status
        /// Nil when the shortcut couldn't be registered.
        var shortcut: Shortcut?
    }

    var onToggleDictation: () -> Void = {}
    var onOpenSettings: () -> Void = {}
    var onRestartEngine: () -> Void = {}
    var currentState: () -> State? = { nil }

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    override init() {
        super.init()
        item.button?.image = Brand.statusIcon(active: false)
        item.button?.toolTip = "bada"
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
    }

    func setActive(_ active: Bool) {
        item.button?.image = Brand.statusIcon(active: active)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let state = currentState() else { return }

        let dictation = menu.addItem(title(for: state.phase), action: #selector(toggleDictation))
        dictation.isEnabled = state.phase == .idle || state.phase == .listening
        if let shortcut = state.shortcut, let equivalent = shortcut.menuKeyEquivalent {
            dictation.keyEquivalent = equivalent.key
            dictation.keyEquivalentModifierMask = equivalent.flags
        } else if state.shortcut == nil {
            menu.addNote("단축키를 쓸 수 없어요 · 설정에서 바꿔 주세요")
        }

        switch state.engineStatus {
        case .ready: break
        case .installing: menu.addNote("음성 엔진 설치 중…")
        case .starting: menu.addNote("음성 모델 불러오는 중…")
        case .downloading: menu.addNote("음성 모델 내려받는 중…")
        case let .failed(message): menu.addItem("\(message) · 다시 시작", action: #selector(restartEngine))
        }

        menu.addItem(.separator())
        menu.addItem("설정…", action: #selector(openSettings), key: ",")
        menu.addItem(.separator())
        menu.addItem("bada 종료", action: #selector(quit), key: "q")

        for item in menu.items where item.action != nil { item.target = self }
    }

    private func title(for phase: DictationController.Phase) -> String {
        switch phase {
        case .idle: return "받아쓰기 시작"
        case .listening: return "끝내고 입력"
        case .transcribing: return "받아쓰는 중…"
        case .polishing: return "다듬는 중…"
        }
    }

    @objc private func toggleDictation() {
        // Let the menu close and focus return to the previous app first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.onToggleDictation() }
    }

    @objc private func openSettings() { onOpenSettings() }
    @objc private func restartEngine() { onRestartEngine() }
    @objc private func quit() { NSApp.terminate(nil) }
}

private extension NSMenu {
    @discardableResult
    func addItem(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        addItem(withTitle: title, action: action, keyEquivalent: key)
    }

    func addNote(_ title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        addItem(item)
    }
}
