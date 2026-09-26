import AppKit
import AVFoundation

/// Runs one dictation at a time: listen → transcribe → polish (optional) → insert at the caret.
final class DictationController {
    enum Phase: Equatable {
        case idle
        case listening
        case transcribing
        case polishing
    }

    private(set) var phase: Phase = .idle {
        didSet { if phase != oldValue { onPhaseChange?() } }
    }

    var onPhaseChange: (() -> Void)?
    /// Something needs fixing in settings, such as a missing permission.
    var onNeedsSettings: (() -> Void)?

    let hud = HUDController()
    private let preferences = Preferences.shared
    private let engine: SpeechEngine
    private let recorder = Recorder()

    /// Changes whenever a dictation starts or ends, so late callbacks from an old one are ignored.
    private var session = 0
    private var field: FocusedField?
    private var recognitionContext = ""
    private var segmentTexts: [Int: String] = [:]
    private var segmentCount = 0
    private var finalSegmentCount: Int?
    private var transcript = ""
    private var polishTask: Task<Void, Never>?
    private var activity: NSObjectProtocol?
    private var recordingLimit: DispatchWorkItem?
    private var transcriptionTimeout: DispatchWorkItem?
    private var lastShortcutPress = Date.distantPast
    private var stoppedAt = Date()
    private var askedForAccessibility = false

    private let longestRecording: TimeInterval = 600
    /// When polishing takes longer than this, offer to insert the transcript as is.
    private let skipOfferDelay: TimeInterval = 3.5

    init(engine: SpeechEngine) {
        self.engine = engine
        recorder.onSegment = { [weak self] segment in self?.transcribe(segment) }
        recorder.onDeviceLost = { [weak self] in self?.stop() }
        hud.model.meter = recorder.meter
        hud.model.onCancel = { [weak self] in self?.cancel() }
        hud.model.onStop = { [weak self] in self?.stop() }
        hud.model.onSkip = { [weak self] in self?.skipPolishing() }
    }

    // MARK: Controls

    /// The global shortcut: start, stop, or skip the LLM step.
    func toggle() {
        let now = Date()
        defer { lastShortcutPress = now }
        // Ignore key repeat and accidental double presses.
        guard now.timeIntervalSince(lastShortcutPress) > 0.3 else { return }
        switch phase {
        case .idle: start()
        case .listening: stop()
        case .polishing: skipPolishing()
        case .transcribing: break
        }
    }

    func start() {
        guard phase == .idle else { return }
        switch engine.status {
        case .installing:
            hud.flash("음성 엔진을 설치하는 중이에요", symbol: "shippingbox", at: FocusedField.current())
            return
        case .downloading:
            hud.flash("음성 모델을 내려받는 중이에요", symbol: "arrow.down.circle", at: FocusedField.current())
            return
        case .failed:
            hud.flash("음성 엔진을 다시 시작할게요", symbol: "arrow.clockwise", tone: .warning, at: FocusedField.current())
            engine.restart()
            return
        case .starting, .ready:
            break
        }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            beginListening()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async { granted ? self.beginListening() : self.microphoneDenied() }
            }
        default:
            microphoneDenied()
        }
    }

    func stop() {
        guard phase == .listening else { return }
        stoppedAt = Date()
        phase = .transcribing
        recordingLimit?.cancel()
        hud.update(.transcribing)
        let session = self.session
        recorder.stop { [weak self] take in
            guard let self, session == self.session else { return }
            let spoke = take.voicedSeconds >= 0.2 && take.seconds >= 0.3
            if self.segmentCount == 0 && !spoke {
                Log.info(String(format: "nothing heard (%.1fs, voiced %.2fs)", take.seconds, take.voicedSeconds))
                self.finish()
                self.hud.flash("들리지 않았어요", symbol: "waveform.slash")
                return
            }
            // A sliver left after the last segment is only room tone.
            if !take.tail.isEmpty && (self.segmentCount == 0 || take.tail.count > 4_000) {
                self.transcribe(take.tail, isLast: true)
            }
            self.finalSegmentCount = self.segmentCount
            self.armTranscriptionTimeout(seconds: 20 + take.seconds * 0.5)
            self.finishTranscriptIfComplete()
        }
    }

    func cancel() {
        guard phase != .idle else { return }
        Log.info("cancelled while \(phase)")
        session += 1
        polishTask?.cancel()
        recorder.cancel()
        finish()
        hud.dismiss()
    }

    // MARK: Flow

    private func beginListening() {
        session += 1
        let session = self.session
        segmentTexts = [:]
        segmentCount = 0
        finalSegmentCount = nil
        transcript = ""
        phase = .listening
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: "받아쓰기")

        // Open the mic before looking for the caret, so the first syllable isn't lost.
        hud.model.isMicrophoneReady = false
        recorder.start(deviceUID: preferences.connectedMicrophoneID) { [weak self] error in
            guard let self, session == self.session else { return }
            if let error {
                Log.info("microphone: \(error.localizedDescription)")
                self.session += 1
                self.finish()
                self.hud.flash("마이크를 열 수 없어요", symbol: "mic.slash.fill", tone: .warning)
            } else {
                self.hud.model.isMicrophoneReady = true
            }
        }

        let field = FocusedField.current()
        self.field = field
        recognitionContext = context(for: field)
        hud.present(.listening, at: field)
        GlobalHotkeys.shared.register(.cancel, .escape) { [weak self] in self?.cancel() }

        let limit = DispatchWorkItem { [weak self] in self?.stop() }
        recordingLimit = limit
        DispatchQueue.main.asyncAfter(deadline: .now() + longestRecording, execute: limit)
    }

    private func transcribe(_ samples: [Float], isLast: Bool = false) {
        let index = segmentCount
        segmentCount += 1
        let session = self.session
        let audio = Recorder.trimmingSilence(samples, leading: index == 0, trailing: isLast)
        engine.transcribe(audio, context: recognitionContext) { [weak self] result in
            guard let self, session == self.session else { return }
            switch result {
            case let .success(text):
                self.segmentTexts[index] = text
                self.finishTranscriptIfComplete()
            case let .failure(error):
                self.fail(error.localizedDescription)
            }
        }
    }

    private func finishTranscriptIfComplete() {
        guard phase == .transcribing, let total = finalSegmentCount, segmentTexts.count == total else { return }
        transcriptionTimeout?.cancel()
        let text = (0..<total)
            .compactMap { segmentTexts[$0]?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !text.isEmpty else {
            finish()
            hud.flash("들리지 않았어요", symbol: "waveform.slash")
            return
        }
        transcript = text
        let llm = preferences.llm
        if llm.isComplete {
            polish(text, with: llm)
        } else {
            insert(text)
        }
    }

    private func polish(_ text: String, with llm: LLMConfig) {
        phase = .polishing
        hud.update(.polishing)
        let session = self.session
        let vocabulary = preferences.vocabularyTerms
        let started = Date()
        DispatchQueue.main.asyncAfter(deadline: .now() + skipOfferDelay) { [weak self] in
            guard let self, session == self.session, self.phase == .polishing else { return }
            self.hud.model.canSkip = true
        }
        polishTask = Task { @MainActor [weak self] in
            let result: Result<String, Error>
            do {
                result = .success(try await Polisher.polish(text, vocabulary: vocabulary, config: llm))
            } catch {
                result = .failure(error)
            }
            guard let self, session == self.session, self.phase == .polishing else { return }
            let seconds = Date().timeIntervalSince(started)
            switch result {
            case let .success(polished):
                Log.info(String(format: "polished %d → %d chars in %.1fs", text.count, polished.count, seconds))
                self.insert(polished)
            case let .failure(error):
                Log.info(String(format: "polishing failed after %.1fs: %@", seconds, error.localizedDescription))
                self.insert(text, note: "다듬지 못해 원문으로 넣었어요")
            }
        }
    }

    private func skipPolishing() {
        guard phase == .polishing else { return }
        Log.info("polishing skipped")
        polishTask?.cancel()
        insert(transcript)
    }

    private func insert(_ text: String, note: String? = nil) {
        let field = self.field
        Log.info(String(format: "inserted %d chars, %.1fs after stop", text.count, Date().timeIntervalSince(stoppedAt)))
        session += 1
        finish()
        if !TextInserter.insert(text, into: field) {
            hud.flash("클립보드에 복사했어요 · ⌘V", symbol: "doc.on.clipboard.fill", tone: .success, duration: 2.6)
            if !askedForAccessibility {
                askedForAccessibility = true
                Permissions.promptForAccessibility()
            }
        } else if let note {
            hud.flash(note, symbol: "exclamationmark.circle.fill", tone: .warning, duration: 2.2)
        } else {
            hud.succeed()
        }
    }

    private func fail(_ message: String) {
        guard phase == .transcribing else { return }
        session += 1
        finish()
        hud.flash(message, symbol: "exclamationmark.triangle.fill", tone: .warning, duration: 2.2)
    }

    /// Back to idle: timers, the esc shortcut and the no-sleep assertion go away.
    private func finish() {
        phase = .idle
        recordingLimit?.cancel()
        transcriptionTimeout?.cancel()
        GlobalHotkeys.shared.unregister(.cancel)
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
    }

    private func microphoneDenied() {
        hud.flash("마이크 권한이 필요해요", symbol: "mic.slash.fill", tone: .warning, duration: 2.4, at: FocusedField.current())
        onNeedsSettings?()
    }

    private func armTranscriptionTimeout(seconds: TimeInterval) {
        transcriptionTimeout?.cancel()
        let session = self.session
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, session == self.session, self.phase == .transcribing else { return }
            self.fail("받아쓰기가 너무 오래 걸려요")
        }
        transcriptionTimeout = timeout
        // A model that is still loading gets extra time.
        let wait = engine.status.isReady ? seconds : seconds + 60
        DispatchQueue.main.asyncAfter(deadline: .now() + wait, execute: timeout)
    }

    /// Vocabulary plus the text before the caret, to help recognition spell names. Never sent anywhere.
    private func context(for field: FocusedField) -> String {
        var parts: [String] = []
        let terms = preferences.vocabularyTerms
        if !terms.isEmpty { parts.append(terms.joined(separator: ", ")) }
        let before = field.textBeforeCaret.trimmingCharacters(in: .whitespacesAndNewlines)
        if !before.isEmpty, !field.isSecure { parts.append(String(before.suffix(300))) }
        return parts.joined(separator: "\n")
    }
}
