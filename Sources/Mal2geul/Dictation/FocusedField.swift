import AppKit
import ApplicationServices

/// Where the user was typing when they pressed the shortcut, read through Accessibility.
struct FocusedField {
    let app: NSRunningApplication?
    /// The caret, or the mouse pointer when the caret can't be found. AppKit screen coordinates.
    let anchor: CGRect
    let isCaret: Bool
    /// Up to 300 characters before the caret. Stays on this Mac: it only helps recognition spell names.
    let textBeforeCaret: String
    let isSecure: Bool

    var screen: NSScreen {
        NSScreen.screens.first { $0.frame.intersects(anchor.insetBy(dx: -1, dy: -1)) }
            ?? NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    static func current() -> FocusedField {
        let app = NSWorkspace.shared.frontmostApplication
        let mouse = NSEvent.mouseLocation
        let pointer = CGRect(x: mouse.x, y: mouse.y - 10, width: 1, height: 20)
        let fallback = FocusedField(app: app, anchor: pointer, isCaret: false, textBeforeCaret: "", isSecure: false)

        // Querying our own process over Accessibility from the main thread can stall.
        guard AXIsProcessTrusted(), let app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return fallback
        }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.2)
        enableAccessibilityTree(of: application, pid: app.processIdentifier)

        guard let value = attribute(kAXFocusedUIElementAttribute, of: application),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return fallback }
        let element = value as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.2)

        let isSecure = (attribute(kAXSubroleAttribute, of: element) as? String) == kAXSecureTextFieldSubrole
        let selection = selectedRange(of: element)
        let text = (isSecure ? nil : selection).map { textBefore($0, in: element) } ?? ""

        if let selection, let caret = caretRect(at: selection, in: element) {
            return FocusedField(app: app, anchor: caret, isCaret: true, textBeforeCaret: text, isSecure: isSecure)
        }
        // No caret geometry. Use the pointer if it is inside the field, else a single-line field's first line.
        if let frame = frame(of: element), frame.width > 4, frame.height > 4, !frame.contains(mouse), frame.height < 64 {
            let lineHeight = min(frame.height, 24)
            let line = CGRect(x: frame.minX + min(frame.width / 2, 120), y: frame.maxY - lineHeight, width: 1, height: lineHeight)
            return FocusedField(app: app, anchor: line, isCaret: false, textBeforeCaret: text, isSecure: isSecure)
        }
        return FocusedField(app: app, anchor: pointer, isCaret: false, textBeforeCaret: text, isSecure: isSecure)
    }

    // MARK: Accessibility

    private static var primedProcesses = Set<pid_t>()

    /// Chromium and Electron apps build their accessibility tree only when asked.
    private static func enableAccessibilityTree(of application: AXUIElement, pid: pid_t) {
        guard primedProcesses.insert(pid).inserted else { return }
        AXUIElementSetAttributeValue(application, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    private static func selectedRange(of element: AXUIElement) -> CFRange? {
        guard let value = attribute(kAXSelectedTextRangeAttribute, of: element),
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range), range.location >= 0 else { return nil }
        return range
    }

    private static func caretRect(at selection: CFRange, in element: AXUIElement) -> CGRect? {
        // An empty range first; some apps only answer for a real character.
        if let rect = bounds(of: CFRange(location: selection.location, length: 0), in: element), rect.height > 1 {
            return rect
        }
        if selection.location > 0,
           let rect = bounds(of: CFRange(location: selection.location - 1, length: 1), in: element), rect.height > 1 {
            return CGRect(x: rect.maxX, y: rect.minY, width: 1, height: rect.height)
        }
        if let rect = bounds(of: CFRange(location: selection.location, length: 1), in: element), rect.height > 1 {
            return CGRect(x: rect.minX, y: rect.minY, width: 1, height: rect.height)
        }
        return nil
    }

    private static func bounds(of range: CFRange, in element: AXUIElement) -> CGRect? {
        var range = range
        guard let parameter = AXValueCreate(.cfRange, &range) else { return nil }
        var result: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, parameter, &result) == .success,
              let result, CFGetTypeID(result) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(result as! AXValue, .cgRect, &rect) else { return nil }
        return appKitRect(rect)
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        guard let position = attribute(kAXPositionAttribute, of: element), CFGetTypeID(position) == AXValueGetTypeID(),
              let size = attribute(kAXSizeAttribute, of: element), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
              AXValueGetValue(size as! AXValue, .cgSize, &extent) else { return nil }
        return appKitRect(CGRect(origin: origin, size: extent))
    }

    private static func textBefore(_ selection: CFRange, in element: AXUIElement) -> String {
        let length = min(selection.location, 300)
        guard length > 0 else { return "" }
        var slice = CFRange(location: selection.location - length, length: length)
        if let parameter = AXValueCreate(.cfRange, &slice) {
            var result: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString, parameter, &result) == .success,
               let text = result as? String {
                return text
            }
        }
        // Fall back to the whole value, but not for huge documents.
        if let count = attribute(kAXNumberOfCharactersAttribute, of: element) as? Int, count > 20_000 { return "" }
        guard let value = attribute(kAXValueAttribute, of: element) as? String else { return "" }
        let utf16 = Array(value.utf16)
        guard selection.location <= utf16.count else { return "" }
        return String(decoding: utf16[(selection.location - length)..<selection.location], as: UTF16.self)
    }

    /// Accessibility uses a top-left origin on the primary display; AppKit uses bottom-left.
    private static func appKitRect(_ rect: CGRect) -> CGRect? {
        guard rect.width.isFinite, rect.height.isFinite, rect.height < 400, rect != .zero else { return nil }
        let primary = NSScreen.screens.first?.frame ?? .zero
        let flipped = CGRect(x: rect.minX, y: primary.maxY - rect.maxY, width: max(rect.width, 1), height: max(rect.height, 1))
        guard NSScreen.screens.contains(where: { $0.frame.insetBy(dx: -2, dy: -2).intersects(flipped) }) else { return nil }
        return flipped
    }

    private static func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
}
