import AppKit
import SwiftUI

enum SettingsMetrics {
    static let fieldWidth: CGFloat = 272
    static let rowHeight: CGFloat = 46
}

extension View {
    /// Bordered, left-aligned text input of the standard width.
    func settingsField() -> some View {
        textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.leading)
            .autocorrectionDisabled()
            .frame(width: SettingsMetrics.fieldWidth)
    }
}

/// A rounded group of rows with an optional title and footnote.
struct Card<Content: View>: View {
    let title: String?
    let accessory: AnyView?
    let footer: String?
    let content: Content

    init(title: String? = nil, accessory: AnyView? = nil, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.accessory = accessory
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                HStack {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Spacer()
                    accessory
                }
                .padding(.horizontal, 4)
            }
            VStack(spacing: 0) { content }
                .padding(.horizontal, 14)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.045)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.6))
            if let footer {
                Text(footer)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }
}

/// Label on the left, control on the right, centered on one line.
struct Row<Content: View>: View {
    let title: String
    let detail: String?
    let content: Content

    init(_ title: String, detail: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.detail = detail
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13))
                if let detail {
                    Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            content
        }
        .padding(.vertical, 8)
        .frame(minHeight: SettingsMetrics.rowHeight)
    }
}

/// App icon, name, tagline and the speech engine's state.
struct Header: View {
    let engineStatus: SpeechEngine.Status
    let retry: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 58, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 0.6))
                .shadow(color: Brand.blue.opacity(0.35), radius: 12, y: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text("bada")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .tracking(-0.5)
                Text(Brand.tagline)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            EngineBadge(status: engineStatus, retry: retry)
        }
    }
}

struct EngineBadge: View {
    let status: SpeechEngine.Status
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            switch status {
            case .ready:
                Circle().fill(Color.green).frame(width: 7, height: 7).shadow(color: .green.opacity(0.6), radius: 3)
                Text("음성 모델 준비됨")
            case .installing:
                ProgressView().controlSize(.mini)
                Text("음성 엔진 설치 중")
            case .starting:
                ProgressView().controlSize(.mini)
                Text("모델 불러오는 중")
            case .downloading:
                ProgressView().controlSize(.mini)
                Text("모델 내려받는 중")
            case let .failed(message):
                Circle().fill(Color.red).frame(width: 7, height: 7)
                Text(message).lineLimit(1)
                Button("다시", action: retry).buttonStyle(.link)
            }
        }
        .font(.system(size: 11.5, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(.quaternary.opacity(0.7)))
        .fixedSize()
    }
}

struct PermissionRow: View {
    let symbol: String
    let title: String
    let detail: String
    let isGranted: Bool
    let request: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(isGranted ? Color.green.gradient : Brand.blue.gradient))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(detail).font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            Spacer()
            if isGranted {
                Label("허용됨", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.green)
            } else {
                Button("허용하기", action: request)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 9)
        .frame(minHeight: SettingsMetrics.rowHeight)
    }
}

/// Masked key field with show/hide and paste-from-clipboard buttons.
struct APIKeyField: View {
    @Binding var key: String
    @State private var isRevealed = false

    var body: some View {
        HStack(spacing: 6) {
            Group {
                if isRevealed {
                    TextField("API 키", text: $key, prompt: Text("sk-…"))
                } else {
                    SecureField("API 키", text: $key, prompt: Text("붙여넣기 ⌘V"))
                }
            }
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.leading)
            .autocorrectionDisabled()

            Button {
                isRevealed.toggle()
            } label: {
                Image(systemName: isRevealed ? "eye.slash" : "eye").frame(width: 18)
            }
            .buttonStyle(.borderless)
            .help(isRevealed ? "가리기" : "보기")

            Button {
                if let pasted = NSPasteboard.general.string(forType: .string) {
                    key = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } label: {
                Image(systemName: "doc.on.clipboard").frame(width: 18)
            }
            .buttonStyle(.borderless)
            .help("클립보드에서 붙여넣기")
        }
    }
}

struct OnOffBadge: View {
    let isOn: Bool

    var body: some View {
        Text(isOn ? "켜짐" : "꺼짐")
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(isOn ? Color.white : Color.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 2.5)
            .background(
                Capsule().fill(
                    isOn
                        ? AnyShapeStyle(LinearGradient(colors: [Brand.violet, Brand.pink], startPoint: .leading, endPoint: .trailing))
                        : AnyShapeStyle(Color.primary.opacity(0.08))
                )
            )
    }
}

/// Result of "연결 확인", including how much the model is allowed to think.
struct ConnectionStatus: View {
    let check: ConnectionCheck
    let isConfigured: Bool

    var body: some View {
        switch check {
        case .idle:
            Text(isConfigured ? "설정한 연결이 응답하는지 확인해요" : "세 칸을 모두 채우면 켜져요")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        case .running:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("확인 중").foregroundStyle(.secondary)
            }
            .font(.system(size: 12))
        case let .succeeded(seconds, reasoningEffort):
            HStack(spacing: 6) {
                Label(String(format: "연결됨 · %.1f초", seconds), systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.green)
                if let label = reasoningLabel(reasoningEffort) {
                    Text(label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(Color.primary.opacity(0.07)))
                        .help("다듬을 때는 모델이 허용하는 가장 낮은 사고 수준으로 보내요")
                }
            }
        case let .failed(message):
            Label(message, systemImage: "xmark.octagon.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.red)
                .lineLimit(2)
                .help(message)
        }
    }

    private func reasoningLabel(_ effort: String?) -> String? {
        switch effort {
        case "none": return "사고 끔"
        case "minimal": return "사고 최소"
        case "low": return "사고 낮음"
        default: return nil
        }
    }
}

/// macOS may take the key press first; say which shortcut and link to its settings.
struct ShortcutConflictNote: View {
    let systemShortcut: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.orange)
            Text("macOS ‘\(systemShortcut)’ 단축키와 같아요. 그쪽을 끄거나 다른 키를 골라 주세요.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button("열기", action: SystemShortcuts.openSettings).buttonStyle(.link)
        }
        .font(.system(size: 11.5))
    }
}

/// Window background with a faint glow behind the header, rendered once.
struct Backdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(nsColor: .windowBackgroundColor)
            Image(nsImage: Backdrop.glow)
                .resizable()
                .frame(width: 720, height: 380)
                .opacity(colorScheme == .dark ? 0.34 : 0.26)
                .offset(x: -250, y: -210)
        }
        .ignoresSafeArea()
    }

    @MainActor private static let glow: NSImage = {
        let renderer = ImageRenderer(
            content: Ellipse()
                .fill(AngularGradient(colors: Brand.sea + [Brand.pink.opacity(0.85), Brand.cyan], center: .center, angle: .degrees(40)))
                .frame(width: 440, height: 150)
                .blur(radius: 58)
                .frame(width: 720, height: 380)
        )
        return renderer.nsImage ?? NSImage()
    }()
}
