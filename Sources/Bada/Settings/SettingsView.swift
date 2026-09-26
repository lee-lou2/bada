import SwiftUI

struct SettingsView: View {
    static let width: CGFloat = 500

    @ObservedObject var preferences: Preferences
    @ObservedObject var engine: SpeechEngine
    @ObservedObject var permissions: Permissions
    @ObservedObject var shortcutRecorder: ShortcutRecorder
    @ObservedObject var microphones: MicrophoneList

    @State private var connection: ConnectionCheck = .idle
    @State private var opensAtLogin = LoginItem.isEnabled
    @State private var loginNote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Header(engineStatus: engine.status, retry: engine.restart)
                .padding(.top, 12)
                .padding(.bottom, 2)

            if !permissions.allGranted {
                permissionsCard
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            dictationCard
            polishingCard
            Card {
                Row("로그인할 때 열기", detail: loginNote) {
                    Toggle("로그인할 때 열기", isOn: $opensAtLogin)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .controlSize(.small)
                }
            }
            Text("Qwen3-ASR 1.7B · MLX · 음성 인식은 이 Mac 안에서만 해요")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 24)
        .padding(.top, 30)
        .padding(.bottom, 22)
        .frame(width: SettingsView.width)
        .fixedSize(horizontal: false, vertical: true)
        .background(Backdrop())
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: permissions.allGranted)
        .onChange(of: opensAtLogin) { _, enabled in loginNote = LoginItem.setEnabled(enabled) }
        .onChange(of: preferences.llm) { _, _ in connection = .idle }
        .onChange(of: preferences.shortcut) { _, _ in permissions.refresh() }
    }

    private var permissionsCard: some View {
        Card(title: "시작하기") {
            PermissionRow(
                symbol: "mic.fill",
                title: "마이크",
                detail: "목소리를 들으려면 필요해요",
                isGranted: permissions.microphone == .authorized,
                request: permissions.requestMicrophone
            )
            Divider()
            PermissionRow(
                symbol: "character.cursor.ibeam",
                title: "손쉬운 사용",
                detail: "커서 자리에 바로 입력하려면 필요해요",
                isGranted: permissions.accessibility,
                request: permissions.requestAccessibility
            )
        }
    }

    private var dictationCard: some View {
        Card(title: "받아쓰기", footer: "단축키를 누르고 말한 뒤 한 번 더 누르면 커서 자리에 들어가요. esc는 취소예요.") {
            Row("단축키") {
                ShortcutField(recorder: shortcutRecorder, shortcut: preferences.shortcut)
            }
            if let conflict = permissions.shortcutConflict, !shortcutRecorder.isRecording {
                ShortcutConflictNote(systemShortcut: conflict)
                    .padding(.top, -2)
                    .padding(.bottom, 10)
            }
            Divider()
            Row("마이크") {
                Picker("마이크", selection: $preferences.microphoneID) {
                    Text(microphones.defaultName.isEmpty ? "시스템 기본" : "시스템 기본 · \(microphones.defaultName)").tag("")
                    ForEach(microphones.inputs) { input in
                        Text(input.name).tag(input.uid)
                    }
                    if !preferences.microphoneID.isEmpty, !microphones.inputs.contains(where: { $0.uid == preferences.microphoneID }) {
                        Text("연결 안 된 마이크").tag(preferences.microphoneID)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            Divider()
            Row("단어장", detail: "이름·용어를 쉼표로 구분") {
                TextField("단어장", text: $preferences.vocabulary, prompt: Text("바다, Qwen, MLX, 김지훈"), axis: .vertical)
                    .lineLimit(1...3)
                    .settingsField()
            }
        }
    }

    private var polishingCard: some View {
        Card(
            title: "LLM 다듬기",
            accessory: AnyView(OnOffBadge(isOn: preferences.llm.isComplete)),
            footer: "음성은 보내지 않고 받아쓴 글만 보내요. 연결이 안 되면 받아쓴 그대로 넣어요."
        ) {
            Row("Base URL") {
                TextField("Base URL", text: $preferences.llmBaseURL, prompt: Text("https://api.openai.com/v1"))
                    .settingsField()
            }
            Divider()
            Row("API 키") {
                APIKeyField(key: $preferences.llmAPIKey)
                    .frame(width: SettingsMetrics.fieldWidth)
            }
            Divider()
            Row("모델") {
                TextField("모델", text: $preferences.llmModel, prompt: Text("gpt-4.1-mini"))
                    .settingsField()
            }
            Divider()
            HStack(spacing: 10) {
                ConnectionStatus(check: connection, isConfigured: preferences.llm.isComplete)
                Spacer(minLength: 8)
                Button("연결 확인", action: checkConnection)
                    .disabled(!preferences.llm.isComplete || connection == .running)
            }
            .frame(minHeight: SettingsMetrics.rowHeight)
        }
    }

    private func checkConnection() {
        connection = .running
        let config = preferences.llm
        Task { @MainActor in
            do {
                let result = try await ChatCompletions.ping(config)
                connection = .succeeded(seconds: result.seconds, reasoningEffort: result.reasoningEffort)
            } catch {
                connection = .failed(error.localizedDescription)
            }
        }
    }
}

enum ConnectionCheck: Equatable {
    case idle
    case running
    case succeeded(seconds: TimeInterval, reasoningEffort: String?)
    case failed(String)
}
