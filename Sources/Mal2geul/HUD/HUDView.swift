import SwiftUI

/// The floating capsule under the caret.
struct HUDView: View {
    @ObservedObject var model: HUDModel

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !model.isAnimating)) { timeline in
            HUDCapsule(model: model, frame: model.frame(at: timeline.date.timeIntervalSinceReferenceDate))
        }
        .frame(width: HUDLayout.panel.width, height: HUDLayout.panel.height, alignment: .top)
    }
}

private struct HUDCapsule: View {
    @ObservedObject var model: HUDModel
    let frame: HUDFrame

    var body: some View {
        let size = model.size
        let still = model.reduceMotion
        // Listening, the capsule swells slightly with the voice.
        let breathing = model.mode == .listening && !still ? 0.028 * frame.energy : 0
        CapsuleBody(frame: frame)
            .frame(width: size.width, height: size.height)
            .overlay(content.frame(width: size.width, height: size.height).clipShape(Capsule()))
            .background(Aurora(frame: frame, size: size))
            .background(Ping(frame: frame, size: size, enabled: !still))
            // Entrance: grows out of the caret.
            .scaleEffect(model.isPresented || still ? 1 + breathing : 0.5, anchor: .top)
            .opacity(model.isPresented ? 1 : 0)
            .blur(radius: model.isPresented || still ? 0 : 7)
            .offset(y: model.isPresented || still ? 0 : -10)
            .padding(.top, HUDLayout.topInset)
            .animation(.spring(response: 0.42, dampingFraction: 0.76), value: model.mode)
            .animation(.spring(response: 0.42, dampingFraction: 0.8), value: model.canSkip)
    }

    @ViewBuilder private var content: some View {
        switch model.mode {
        case .listening:
            HStack(spacing: 0) {
                RoundButton(kind: .cancel, action: model.onCancel)
                Spacer(minLength: 0)
                ZStack {
                    // Honest about slow microphones: no bars until sound can actually arrive.
                    if !model.isMicrophoneReady && frame.sinceModeChange > 0.25 {
                        Shimmer(text: "마이크 연결 중", now: frame.now)
                    } else {
                        RippleBars(values: frame.bars)
                    }
                }
                .frame(width: 112, height: 26)
                .animation(.easeOut(duration: 0.2), value: model.isMicrophoneReady)
                Spacer(minLength: 0)
                RoundButton(kind: .stop, action: model.onStop)
            }
            .padding(.horizontal, 6)
            .transition(.opacity.combined(with: .scale(scale: 0.92)))

        case .transcribing:
            HStack(spacing: 0) {
                RoundButton(kind: .cancel, action: model.onCancel)
                Loader(now: frame.now)
                    .frame(width: 17, height: 16)
                    .padding(.leading, 12)
                Shimmer(text: "받아쓰는 중", now: frame.now)
                    .padding(.leading, 9)
                Spacer(minLength: 0)
            }
            .padding(.leading, 6)
            .transition(.opacity.combined(with: .scale(scale: 0.92)))

        case .polishing:
            HStack(spacing: 0) {
                RoundButton(kind: .cancel, action: model.onCancel)
                Sparkle(now: frame.now)
                    .frame(width: 16, height: 16)
                    .padding(.leading, 12)
                Shimmer(text: "다듬는 중", now: frame.now)
                    .padding(.leading, 8)
                Spacer(minLength: 0)
                if model.canSkip {
                    SkipButton(action: model.onSkip)
                        .padding(.trailing, 6)
                        .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .trailing)))
                }
            }
            .padding(.leading, 6)
            .transition(.opacity.combined(with: .scale(scale: 0.92)))

        case .done:
            Checkmark(progress: min(1, frame.sinceModeChange / 0.3))
                .stroke(Color.white, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                .frame(width: 14, height: 11)
                .transition(.opacity.combined(with: .scale(scale: 0.6)))

        case let .notice(text, symbol, tone):
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tone.iconColor)
                    .frame(width: 16)
                Text(text)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.94))
                    .lineLimit(1)
            }
            .padding(.leading, 15)
            .padding(.trailing, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.opacity)
        }
    }
}

private extension HUDModel.Tone {
    var iconColor: Color {
        switch self {
        case .calm: return Color(hex: 0x9FEFFF)
        case .warning: return Color(hex: 0xFFC56B)
        case .success: return Brand.mint
        }
    }
}

/// Bioluminescent halo that breathes with the voice.
private struct Aurora: View {
    let frame: HUDFrame
    let size: CGSize

    var body: some View {
        let energy = frame.energy
        let gradient = AngularGradient(colors: frame.palette, center: .center, angle: frame.angle)
        ZStack {
            // Wide bloom, slightly low: light rising from the water.
            Capsule()
                .fill(gradient)
                .frame(width: size.width + 18 + 40 * energy, height: size.height + 12 + 24 * energy)
                .blur(radius: 15 + 10 * energy)
                .opacity(0.5 + 0.5 * energy)
                .offset(y: 3 + 2 * energy)
            // Tight halo along the edge.
            Capsule()
                .strokeBorder(gradient, lineWidth: 5)
                .frame(width: size.width + 5, height: size.height + 5)
                .blur(radius: 4.5)
                .opacity(0.55 + 0.45 * energy)
        }
        .allowsHitTesting(false)
    }
}

/// A ring that leaves the capsule when it appears and when the text lands.
private struct Ping: View {
    let frame: HUDFrame
    let size: CGSize
    let enabled: Bool

    var body: some View {
        let progress = frame.sincePing / 0.75
        if enabled && progress >= 0 && progress < 1 {
            let eased = 1 - pow(1 - progress, 3)
            Capsule()
                .strokeBorder(AngularGradient(colors: frame.palette, center: .center, angle: frame.angle), lineWidth: 1.6)
                .frame(width: size.width + 46 * eased, height: size.height + 26 * eased)
                .opacity(0.75 * (1 - progress))
                .allowsHitTesting(false)
        }
    }
}

private struct CapsuleBody: View {
    let frame: HUDFrame

    var body: some View {
        let gradient = AngularGradient(colors: frame.palette, center: .center, angle: frame.angle)
        Capsule()
            .fill(LinearGradient(colors: [Color(hex: 0x1C212D), Brand.ink], startPoint: .top, endPoint: .bottom))
            // Glass sheen on the upper half.
            .overlay(
                Capsule()
                    .fill(LinearGradient(colors: [.white.opacity(0.12), .white.opacity(0)], startPoint: .top, endPoint: .center))
                    .padding(1)
            )
            // Light leaking in from the rim.
            .overlay(
                Capsule()
                    .strokeBorder(gradient, lineWidth: 6)
                    .blur(radius: 5)
                    .opacity(0.16 + 0.3 * frame.energy)
                    .clipShape(Capsule())
            )
            // Lit rim.
            .overlay(Capsule().strokeBorder(gradient, lineWidth: 1.1).opacity(0.45 + 0.55 * frame.energy))
            .overlay(
                Capsule().strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0)], startPoint: .top, endPoint: .center),
                    lineWidth: 0.6
                )
            )
            .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
    }
}
