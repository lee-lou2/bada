import AppKit
import SwiftUI

/// Sizes of the capsule and the transparent panel around it.
enum HUDLayout {
    static let panel = CGSize(width: 380, height: 140)
    /// Room above the capsule for the glow.
    static let topInset: CGFloat = 34
    static let height: CGFloat = 40
    static let listeningWidth: CGFloat = 204
    static let maxWidth: CGFloat = 260
    /// Space between the caret and the capsule.
    static let gap: CGFloat = 9
    static let labelFont = NSFont.systemFont(ofSize: 13, weight: .semibold)

    static func width(of text: String) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: labelFont]).width)
    }
}

/// What the capsule shows, plus the animation clock that drives it.
final class HUDModel: ObservableObject {
    enum Tone: Equatable { case calm, warning, success }

    enum Mode: Equatable {
        case listening
        case transcribing
        case polishing
        case done
        case notice(String, symbol: String, tone: Tone)
    }

    @Published var mode: Mode = .listening
    @Published var isPresented = false
    /// Drives the animation clock; false while hidden.
    @Published var isAnimating = false
    /// False while a slow microphone (iPhone, Bluetooth) is still opening.
    @Published var isMicrophoneReady = true
    /// Polishing is slow: offer to insert the transcript as is.
    @Published var canSkip = false
    /// The system's Reduce Motion setting.
    var reduceMotion = false

    var meter: LevelMeter?
    var onCancel: () -> Void = {}
    var onStop: () -> Void = {}
    var onSkip: () -> Void = {}

    private let ripple = RippleHistory()
    private var modeChangedAt: Double = 0
    private var pingStartedAt: Double = 0
    private var angle: Double = 0
    private var spin: Double = 30
    private var lastTick: Double = 0
    private var colors = HUDModel.stops(Brand.listening)
    private var fromColors = HUDModel.stops(Brand.listening)
    private var toColors = HUDModel.stops(Brand.listening)

    func setMode(_ next: Mode, at now: Double = Date.timeIntervalSinceReferenceDate) {
        guard next != mode else { return }
        fromColors = colors
        toColors = HUDModel.stops(HUDModel.palette(for: next))
        modeChangedAt = now
        if next == .done { pingStartedAt = now } // a second ripple: the words landed
        mode = next
    }

    /// Resets the clock for a fresh entrance.
    func prepareEntrance(at now: Double = Date.timeIntervalSinceReferenceDate) {
        pingStartedAt = now
        modeChangedAt = now
        colors = HUDModel.stops(HUDModel.palette(for: mode))
        fromColors = colors
        toColors = colors
        ripple.reset()
    }

    var size: CGSize {
        let height = HUDLayout.height
        switch mode {
        case .listening:
            return CGSize(width: HUDLayout.listeningWidth, height: height)
        case .transcribing:
            return CGSize(width: 6 + 28 + 12 + 17 + 9 + HUDLayout.width(of: "받아쓰는 중") + 18, height: height)
        case .polishing:
            let skip = canSkip ? SkipButton.width - 4 : 0
            return CGSize(width: 6 + 28 + 12 + 16 + 8 + HUDLayout.width(of: "다듬는 중") + 18 + skip, height: height)
        case .done:
            return CGSize(width: height, height: height)
        case let .notice(text, _, _):
            return CGSize(width: min(HUDLayout.maxWidth, 15 + 16 + 8 + HUDLayout.width(of: text) + 18), height: height)
        }
    }

    /// Advances the animation to `now` and returns what to draw. Called once per displayed frame.
    func frame(at now: Double) -> HUDFrame {
        if now != lastTick {
            let dt = lastTick == 0 ? 1.0 / 60 : max(0, min(0.1, now - lastTick))
            lastTick = now
            ripple.advance(to: now, level: mode == .listening ? meter?.read() ?? 0 : 0)

            let targetSpin: Double
            switch mode {
            case .listening: targetSpin = 28 + 70 * Double(ripple.glow)
            case .transcribing: targetSpin = 150
            case .polishing: targetSpin = 190
            case .done: targetSpin = 90
            case .notice: targetSpin = 22
            }
            spin += ((reduceMotion ? 0 : targetSpin) - spin) * (1 - exp(-dt / 0.35))
            angle = (angle + spin * dt).truncatingRemainder(dividingBy: 360)

            let progress = min(1, max(0, (now - modeChangedAt) / 0.55))
            let eased = progress * progress * (3 - 2 * progress)
            colors = zip(fromColors, toColors).map { $0.blended(withFraction: eased, of: $1) ?? $1 }
        }

        let energy: CGFloat
        switch mode {
        case .listening: energy = CGFloat(ripple.glow)
        case .transcribing, .polishing: energy = 0.42 + 0.1 * CGFloat(sin(now * 3.1))
        case .done: energy = max(0.3, 1 - CGFloat(now - modeChangedAt) * 1.4)
        case .notice: energy = 0.25
        }
        return HUDFrame(
            now: now,
            bars: ripple.bars(),
            energy: energy,
            angle: .degrees(angle),
            palette: colors.map { Color(nsColor: $0) },
            sinceModeChange: now - modeChangedAt,
            sincePing: now - pingStartedAt
        )
    }

    private static func palette(for mode: Mode) -> [Color] {
        switch mode {
        case .listening: return Brand.listening
        case .transcribing: return Brand.transcribing
        case .polishing: return Brand.polishing
        case .done: return Brand.success
        case .notice(_, _, .calm): return Brand.transcribing
        case .notice(_, _, .warning): return Brand.warning
        case .notice(_, _, .success): return Brand.success
        }
    }

    /// Resamples a palette to a fixed number of stops so any two can be blended.
    private static func stops(_ palette: [Color]) -> [NSColor] {
        let source = palette.map { NSColor($0).usingColorSpace(.sRGB) ?? .white }
        let count = 8
        return (0..<count).map { index in
            let position = Double(index) / Double(count) * Double(source.count)
            let lower = Int(position) % source.count
            let upper = (lower + 1) % source.count
            return source[lower].blended(withFraction: position - floor(position), of: source[upper]) ?? source[lower]
        } + [source[0]]
    }
}

/// Everything one animation frame needs.
struct HUDFrame {
    var now: Double
    var bars: [CGFloat]
    /// 0...1: how brightly the capsule glows.
    var energy: CGFloat
    var angle: Angle
    var palette: [Color]
    var sinceModeChange: Double
    var sincePing: Double
}

/// The voice as ripples: the center bar is now, outer bars are a moment ago.
/// Bar heights come only from the microphone level.
final class RippleHistory {
    static let barCount = 15
    private let step = 1.0 / 45.0
    private let spacing = 1.3
    private var history = [Float](repeating: 0, count: 40)
    private var level: Float = 0
    private(set) var glow: Float = 0
    private var carry: Double = 0
    private var last: Double = 0

    func reset() {
        history = [Float](repeating: 0, count: history.count)
        level = 0
        glow = 0
        carry = 0
        last = 0
    }

    func advance(to now: Double, level input: Float) {
        let dt = last == 0 ? 1.0 / 60 : max(0, min(0.1, now - last))
        last = now
        let attack = Float(1 - exp(-dt / 0.02))
        let release = Float(1 - exp(-dt / 0.11))
        level += (input - level) * (input > level ? attack : release)
        let rise = Float(1 - exp(-dt / 0.08))
        let fall = Float(1 - exp(-dt / 0.55))
        glow += (level - glow) * (level > glow ? rise : fall)
        carry += dt
        while carry >= step {
            carry -= step
            history.removeLast()
            history.insert(level, at: 0)
        }
    }

    func bars() -> [CGFloat] {
        let center = RippleHistory.barCount / 2
        return (0..<RippleHistory.barCount).map { index in
            let distance = abs(index - center)
            let taper = 1 - 0.45 * pow(Double(distance) / Double(center), 1.8)
            return CGFloat(Double(level(stepsAgo: Double(distance) * spacing)) * taper)
        }
    }

    /// Interpolated between samples so ripples glide instead of stepping.
    private func level(stepsAgo age: Double) -> Float {
        let fraction = carry / step
        if age <= fraction {
            let weight = fraction > 0 ? Float(age / fraction) : 0
            return level + (history[0] - level) * weight
        }
        let position = age - fraction
        let index = Int(position)
        guard index + 1 < history.count else { return history.last ?? 0 }
        let weight = Float(position - Double(index))
        return history[index] + (history[index + 1] - history[index]) * weight
    }
}
