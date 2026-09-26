import AppKit

/// A menu bar-only app has no main menu, so ⌘C/⌘V/⌘A would do nothing in settings text fields.
/// This one is never visible; it only provides the standard key equivalents.
enum MainMenu {
    static func install() {
        let main = NSMenu()

        let app = NSMenu(title: "말2글")
        app.addItem(withTitle: "말2글 가리기", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        main.addSubmenu(app)

        let edit = NSMenu(title: "편집")
        edit.addItem(withTitle: "실행 취소", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "실행 복귀", action: Selector(("redo:")), keyEquivalent: "z").keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "오려두기", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "복사하기", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "붙여넣기", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "전체 선택", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addSubmenu(edit)

        let window = NSMenu(title: "윈도우")
        window.addItem(withTitle: "닫기", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "최소화", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        main.addSubmenu(window)

        NSApp.mainMenu = main
    }
}

private extension NSMenu {
    func addSubmenu(_ submenu: NSMenu) {
        let item = NSMenuItem()
        item.submenu = submenu
        addItem(item)
    }
}
