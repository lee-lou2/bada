import AppKit
import Carbon
import SwiftUI

/// Captures a new shortcut while the settings window is key.
final class ShortcutRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    /// Modifiers held right now, shown while recording.
    @Published private(set) var heldModifiers: NSEvent.ModifierFlags = []
    @Published private(set) var message: String?
    @Published private(set) var isError = false

    /// Pauses the global shortcut so pressing it here doesn't start a dictation.
    var suspendShortcut: () -> Void = {}
    /// Applies a new shortcut, or restores the current one when nil. False if macOS refused it.
    var applyShortcut: (Shortcut?) -> Bool = { _ in true }

    private var monitor: Any?

    func toggle() {
        isRecording ? finish(with: nil) : begin()
    }

    func resetToStandard() {
        let applied = applyShortcut(.standard)
        showResult(applied: applied)
    }

    /// The window closed mid-capture: put the current shortcut back.
    func cancel() {
        if isRecording { finish(with: nil) }
    }

    func showUnavailable() {
        showResult(applied: false)
    }

    private func begin() {
        isRecording = true
        isError = false
        message = "⌃ ⌥ ⌘ 중 하나와 함께 · esc 취소"
        heldModifiers = []
        suspendShortcut()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, self.isRecording else { return event }
            let modifiers = event.modifierFlags.intersection([.control, .option, .shift, .command])
            if event.type == .flagsChanged {
                self.heldModifiers = modifiers
            } else if event.keyCode == UInt16(kVK_Escape) && modifiers.isEmpty {
                self.finish(with: nil)
            } else if Shortcut(event: event).isValid {
                self.finish(with: Shortcut(event: event))
            } else {
                self.message = "⌃ ⌥ ⌘ 중 하나와 함께 눌러 주세요"
            }
            return nil
        }
    }

    private func finish(with shortcut: Shortcut?) {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        heldModifiers = []
        let applied = applyShortcut(shortcut)
        showResult(applied: shortcut == nil || applied)
    }

    private func showResult(applied: Bool) {
        isError = !applied
        message = applied ? nil : "다른 앱이 쓰는 단축키예요"
    }
}

/// Shows the shortcut as keycaps; click to record a new one.
struct ShortcutField: View {
    @ObservedObject var recorder: ShortcutRecorder
    let shortcut: Shortcut

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 8) {
                if shortcut != .standard && !recorder.isRecording {
                    Button(action: recorder.resetToStandard) {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .buttonStyle(.borderless)
                    .help("기본값 ⌃⌥Space로")
                }
                Button(action: recorder.toggle) {
                    HStack(spacing: 4) { keycaps }
                        .frame(minHeight: 26)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(recorder.isRecording ? Color.accentColor.opacity(0.12) : .clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(recorder.isRecording ? Color.accentColor.opacity(0.9) : .clear, lineWidth: 1.2)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(recorder.isRecording ? "esc로 취소" : "눌러서 바꾸기")
            }
            if let message = recorder.message {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(recorder.isError ? Color.red : Color.secondary)
            }
        }
    }

    @ViewBuilder private var keycaps: some View {
        if !recorder.isRecording {
            ForEach(Array(shortcut.keys.enumerated()), id: \.offset) { Keycap(label: $0.element, isLit: false) }
        } else if recorder.heldModifiers.isEmpty {
            Text("새 단축키를 누르세요")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 6)
        } else {
            ForEach(Shortcut.symbols(recorder.heldModifiers), id: \.self) { Keycap(label: $0, isLit: true) }
        }
    }
}

private struct Keycap: View {
    let label: String
    let isLit: Bool

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(isLit ? Color.accentColor : Color.primary)
            .padding(.horizontal, label.count > 1 ? 8 : 0)
            .frame(minWidth: 24, minHeight: 22)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(0.18), radius: 0.5, y: 1)
            )
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.6))
    }
}
