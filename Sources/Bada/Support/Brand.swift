import AppKit
import SwiftUI

/// bada = 받아(쓰기) + 바다. A night sea that lights up when you speak.
enum Brand {
    static let tagline = "말하면, 받아 적습니다."

    // Capsule body.
    static let ink = Color(hex: 0x07090E)

    // Bioluminescence.
    static let cyan = Color(hex: 0x42E8FF)
    static let aqua = Color(hex: 0x2FD3C9)
    static let blue = Color(hex: 0x3B6CFF)
    static let violet = Color(hex: 0x8C5CFF)
    static let pink = Color(hex: 0xFF5CC6)
    static let amber = Color(hex: 0xFFB054)
    static let mint = Color(hex: 0x3EF0A8)
    static let coral = Color(hex: 0xFF6B6B)

    /// Listening: voice on the water.
    static let sea: [Color] = [cyan, blue, violet, blue, aqua, cyan]
    /// Transcribing: calm and cool.
    static let tide: [Color] = [cyan, blue, cyan, aqua, blue, cyan]
    /// Polishing with the LLM.
    static let magic: [Color] = [violet, pink, amber, pink, violet, blue, violet]
    static let success: [Color] = [mint, cyan, mint, aqua, mint]
    static let warning: [Color] = [amber, coral, amber, amber]

    /// Menu bar icon: a capsule holding a ripple. Filled while a dictation runs.
    static func statusIcon(active: Bool) -> NSImage {
        let ripple: [CGFloat] = [0.34, 0.66, 1.0, 0.66, 0.34]
        let image = NSImage(size: NSSize(width: 22, height: 16), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let body = CGRect(x: 1.5, y: 2.5, width: rect.width - 3, height: rect.height - 5)
            let radius = body.height / 2
            let barWidth: CGFloat = 1.7
            let gap: CGFloat = 1.55
            let total = barWidth * CGFloat(ripple.count) + gap * CGFloat(ripple.count - 1)
            let bars = ripple.enumerated().map { index, value -> CGPath in
                let height = max(barWidth, (body.height - 4.2) * value)
                let bar = CGRect(
                    x: body.midX - total / 2 + CGFloat(index) * (barWidth + gap),
                    y: body.midY - height / 2,
                    width: barWidth,
                    height: height
                )
                return CGPath(roundedRect: bar, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil)
            }
            context.setFillColor(NSColor.black.cgColor)
            context.setStrokeColor(NSColor.black.cgColor)
            if active {
                context.addPath(CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil))
                context.fillPath()
                context.setBlendMode(.clear)
            } else {
                context.setLineWidth(1.4)
                let outline = body.insetBy(dx: 0.2, dy: 0.2)
                context.addPath(CGPath(roundedRect: outline, cornerWidth: radius, cornerHeight: radius, transform: nil))
                context.strokePath()
            }
            bars.forEach(context.addPath)
            context.fillPath()
            return true
        }
        image.isTemplate = true
        return image
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}
