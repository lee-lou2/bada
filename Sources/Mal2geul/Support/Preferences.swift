import Combine
import Foundation

/// User settings. Each change is saved immediately.
final class Preferences: ObservableObject {
    static let shared = Preferences()

    /// Core Audio UID of the chosen microphone. Empty means the system default.
    @Published var microphoneID: String {
        didSet { defaults.set(microphoneID, forKey: Key.microphone) }
    }

    @Published var shortcut: Shortcut {
        didSet {
            defaults.set(Int(shortcut.keyCode), forKey: Key.shortcutKey)
            defaults.set(Int(shortcut.modifiers), forKey: Key.shortcutModifiers)
        }
    }

    /// Names and terms, separated by commas. Used by recognition and by the LLM.
    @Published var vocabulary: String {
        didSet { defaults.set(vocabulary, forKey: Key.vocabulary) }
    }

    @Published var llmBaseURL: String {
        didSet { defaults.set(llmBaseURL, forKey: Key.llmBaseURL) }
    }

    @Published var llmModel: String {
        didSet { defaults.set(llmModel, forKey: Key.llmModel) }
    }

    @Published var llmAPIKey: String {
        didSet { scheduleKeySave() }
    }

    var didLaunchBefore: Bool {
        get { defaults.bool(forKey: Key.didLaunchBefore) }
        set { defaults.set(newValue, forKey: Key.didLaunchBefore) }
    }

    private let defaults = UserDefaults.standard
    private var pendingKeySave: DispatchWorkItem?

    private init() {
        microphoneID = defaults.string(forKey: Key.microphone) ?? ""
        if defaults.object(forKey: Key.shortcutKey) != nil {
            shortcut = Shortcut(
                keyCode: UInt32(defaults.integer(forKey: Key.shortcutKey)),
                modifiers: UInt32(defaults.integer(forKey: Key.shortcutModifiers))
            )
        } else {
            shortcut = .standard
        }
        vocabulary = defaults.string(forKey: Key.vocabulary) ?? ""
        llmBaseURL = defaults.string(forKey: Key.llmBaseURL) ?? ""
        llmModel = defaults.string(forKey: Key.llmModel) ?? ""
        llmAPIKey = APIKeyStore.read()
    }

    /// Polishing is on only when all three values are present.
    var llm: LLMConfig {
        LLMConfig(
            baseURL: llmBaseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            apiKey: llmAPIKey.trimmingCharacters(in: .whitespacesAndNewlines),
            model: llmModel.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    /// Vocabulary as a clean list, in the order written, without duplicates.
    var vocabularyTerms: [String] {
        var seen = Set<String>()
        return vocabulary
            .components(separatedBy: CharacterSet(charactersIn: ",，、;\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    /// The chosen microphone if it is still connected; nil means the system default.
    var connectedMicrophoneID: String? {
        guard !microphoneID.isEmpty, AudioDevices.deviceID(forUID: microphoneID) != nil else { return nil }
        return microphoneID
    }

    /// Writes a pending API key change now (on quit or when settings close).
    func flush() {
        pendingKeySave?.perform()
        pendingKeySave = nil
    }

    private func scheduleKeySave() {
        pendingKeySave?.cancel()
        let key = llmAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let work = DispatchWorkItem { APIKeyStore.write(key) }
        pendingKeySave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private enum Key {
        static let microphone = "microphoneID"
        static let shortcutKey = "shortcut.keyCode"
        static let shortcutModifiers = "shortcut.modifiers"
        static let vocabulary = "vocabulary"
        static let llmBaseURL = "llm.baseURL"
        static let llmModel = "llm.model"
        static let didLaunchBefore = "didLaunchBefore"
    }
}
