import SwiftUI

/// The waveform: 15 bars whose heights come only from the microphone level.
struct RippleBars: View {
    let values: [CGFloat]

    var body: some View {
        Canvas { context, size in
            guard values.count > 1 else { return }
            let barWidth: CGFloat = 3
            let gap = (size.width - barWidth * CGFloat(values.count)) / CGFloat(values.count - 1)
            for (index, value) in values.enumerated() {
                let level = min(max(value, 0), 1)
                let height = 3 + level * (size.height - 3)
                let bar = CGRect(x: CGFloat(index) * (barWidth + gap), y: (size.height - height) / 2, width: barWidth, height: height)
                // Louder bars glow brighter and a touch cyan.
                let glow = min(1, level * 1.8)
                let color = Color(red: 1 - 0.28 * glow, green: 1 - 0.04 * glow, blue: 1).opacity(0.52 + 0.48 * glow)
                context.fill(Path(roundedRect: bar, cornerRadius: barWidth / 2), with: .color(color))
            }
        }
    }
}

/// ✕ (cancel) and ■ (stop), clearly distinct from the dark capsule.
struct RoundButton: View {
    enum Kind { case cancel, stop }

    let kind: Kind
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                switch kind {
                case .cancel:
                    Circle().fill(Color.white.opacity(isHovered ? 0.22 : 0.13))
                    Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.6)
                    Image(systemName: "xmark")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                case .stop:
                    Circle().fill(Color.white)
                    Circle().fill(Brand.cyan.opacity(isHovered ? 0.18 : 0))
                    RoundedRectangle(cornerRadius: 2.6, style: .continuous)
                        .fill(Brand.ink)
                        .frame(width: 10, height: 10)
                }
            }
            .frame(width: 28, height: 28)
            .scaleEffect(isHovered ? 1.07 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isHovered)
            .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .onHover { isHovered = $0 }
        .help(kind == .stop ? "끝내고 입력" : "취소 (esc)")
        .accessibilityLabel(kind == .stop ? "중지" : "취소")
    }
}

/// "Insert now": use the transcript without waiting for the LLM.
struct SkipButton: View {
    static let width: CGFloat = 76

    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "return")
                    .font(.system(size: 10, weight: .bold))
                Text("바로 넣기")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(Brand.ink)
            .frame(width: SkipButton.width, height: 28)
            .background(Capsule().fill(Color.white.opacity(isHovered ? 1 : 0.92)))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .onHover { isHovered = $0 }
        .help("다듬기를 건너뛰고 받아쓴 그대로 넣기")
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// A label with light sweeping through it.
struct Shimmer: View {
    let text: String
    let now: Double

    var body: some View {
        let phase = (now / 1.5).truncatingRemainder(dividingBy: 1) * 2.2 - 0.6
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.55), location: 0),
                        .init(color: .white, location: 0.5),
                        .init(color: .white.opacity(0.55), location: 1),
                    ],
                    startPoint: UnitPoint(x: phase - 0.45, y: 0.5),
                    endPoint: UnitPoint(x: phase + 0.45, y: 0.5)
                )
            )
            .lineLimit(1)
            .fixedSize()
    }
}

/// Four bars rolling while the speech engine works.
struct Loader: View {
    let now: Double

    var body: some View {
        Canvas { context, size in
            let count = 4
            let barWidth: CGFloat = 2.6
            let gap = (size.width - barWidth * CGFloat(count)) / CGFloat(count - 1)
            for index in 0..<count {
                let wave = 0.5 + 0.5 * sin(now * 7.5 - Double(index) * 0.85)
                let height = 4 + CGFloat(wave) * (size.height - 4)
                let bar = CGRect(x: CGFloat(index) * (barWidth + gap), y: (size.height - height) / 2, width: barWidth, height: height)
                context.fill(Path(roundedRect: bar, cornerRadius: barWidth / 2), with: .color(Brand.cyan.opacity(0.55 + 0.45 * wave)))
            }
        }
    }
}

/// Twinkles while the LLM polishes.
struct Sparkle: View {
    let now: Double

    var body: some View {
        let pulse = 0.5 + 0.5 * sin(now * 4.2)
        Image(systemName: "sparkles")
            .font(.system(size: 13.5, weight: .semibold))
            .foregroundStyle(LinearGradient(colors: [Color(hex: 0xC6A8FF), Brand.pink, Brand.amber], startPoint: .topLeading, endPoint: .bottomTrailing))
            .scaleEffect(0.92 + 0.12 * pulse)
            .rotationEffect(.degrees(6 * sin(now * 2.1)))
            .shadow(color: Brand.pink.opacity(0.35 + 0.35 * pulse), radius: 5)
    }
}

/// A check mark drawn from left to right as `progress` goes from 0 to 1.
struct Checkmark: Shape {
    var progress: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.05))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.36, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path.trimmedPath(from: 0, to: max(0.001, progress))
    }
}
