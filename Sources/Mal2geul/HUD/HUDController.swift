import AppKit
import SwiftUI

/// Shows the capsule right under the caret and runs its entrances and exits.
final class HUDController {
    let model = HUDModel()
    private let panel = HUDPanel()
    private var pendingDismissal: DispatchWorkItem?
    private var field: FocusedField?

    init() {
        let host = HUDHostingView(rootView: HUDView(model: model))
        host.frame = NSRect(origin: .zero, size: HUDLayout.panel)
        host.sizingOptions = []
        panel.contentView = host
    }

    func present(_ mode: HUDModel.Mode, at field: FocusedField) {
        pendingDismissal?.cancel()
        self.field = field
        place(near: field)
        model.canSkip = false
        model.setMode(mode)
        guard !panel.isVisible || !model.isPresented else { return }

        model.isPresented = false
        model.isAnimating = true
        model.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        model.prepareEntrance()
        panel.orderFrontRegardless()
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.66)) { self.model.isPresented = true }
        }
    }

    func update(_ mode: HUDModel.Mode) {
        pendingDismissal?.cancel()
        if mode != .polishing { model.canSkip = false }
        model.setMode(mode)
    }

    /// A short message, then away. Shown where the capsule was, or at `field`.
    func flash(_ text: String, symbol: String, tone: HUDModel.Tone = .calm, duration: TimeInterval = 1.7, at field: FocusedField? = nil) {
        let mode = HUDModel.Mode.notice(text, symbol: symbol, tone: tone)
        if panel.isVisible && model.isPresented {
            update(mode)
        } else {
            present(mode, at: field ?? self.field ?? FocusedField.current())
        }
        dismiss(after: duration)
    }

    func succeed() {
        update(.done)
        dismiss(after: 0.62)
    }

    func dismiss(after delay: TimeInterval = 0) {
        pendingDismissal?.cancel()
        let dismissal = DispatchWorkItem { [weak self] in
            guard let self else { return }
            withAnimation(.easeIn(duration: 0.2)) { self.model.isPresented = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) { [weak self] in
                guard let self, !self.model.isPresented else { return }
                self.panel.orderOut(nil)
                self.model.isAnimating = false
            }
        }
        pendingDismissal = dismissal
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: dismissal)
    }

    /// Centers the capsule under the caret; above it when there is no room below.
    private func place(near field: FocusedField) {
        let visible = field.screen.visibleFrame
        let anchor = field.anchor
        let panelSize = HUDLayout.panel
        let gap = HUDLayout.gap + (field.isCaret ? 0 : 8)

        var capsuleTop = anchor.minY - gap
        if capsuleTop - HUDLayout.height < visible.minY + 10 {
            capsuleTop = anchor.maxY + gap + HUDLayout.height
        }
        capsuleTop = min(capsuleTop, visible.maxY - 6)

        let margin = (panelSize.width - HUDLayout.maxWidth) / 2
        var x = anchor.midX - panelSize.width / 2
        x = max(x, visible.minX + 8 - margin)
        x = min(x, visible.maxX - 8 - margin - HUDLayout.maxWidth)
        let y = capsuleTop + HUDLayout.topInset - panelSize.height
        panel.setFrame(NSRect(x: round(x), y: round(y), width: panelSize.width, height: panelSize.height), display: false)
    }
}

/// A borderless panel that never takes focus, so typing stays in the user's app.
final class HUDPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: HUDLayout.panel),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
        isExcludedFromWindowsMenu = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Buttons respond on the first click even though the panel is never key.
final class HUDHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
