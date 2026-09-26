import Combine
import Foundation

/// Keeps Qwen3-ASR loaded in a child process (`engine.py`) and talks to it over pipes.
///
/// Each request is one JSON header line followed by raw 16 kHz float32 audio; each answer is one
/// JSON line. The child exits when its stdin closes, so it never outlives the app.
final class SpeechEngine: ObservableObject {
    enum Status: Equatable {
        /// First launch or an update: setting up Python and the packages.
        case installing
        case starting
        /// First launch: fetching the model (about 2 GB).
        case downloading
        case ready
        case failed(String)

        var isReady: Bool { self == .ready }
    }

    enum Failure: LocalizedError {
        case unavailable(String)
        case recognition

        var errorDescription: String? {
            switch self {
            case let .unavailable(message): return message
            case .recognition: return "받아쓰지 못했어요"
            }
        }
    }

    typealias Completion = (Result<String, Error>) -> Void

    @Published private(set) var status: Status = .starting

    private var process: Process?
    private var input: FileHandle?
    private var output = Data()
    private var nextRequestID = 1
    private var waiting: [Int: Completion] = [:]
    private var queued: [(id: Int, header: Data, audio: Data)] = []
    private var recentExits: [Date] = []
    private var isStopping = false
    private var isInstalling = false
    private let writer = DispatchQueue(label: "app.bada.engine.writer", qos: .userInitiated)

    // MARK: Lifecycle

    func start() {
        guard process == nil, !isInstalling else { return }
        isStopping = false
        guard EngineInstaller.isInstalled else {
            install()
            return
        }
        guard let script = Bundle.main.url(forResource: "engine", withExtension: "py") else {
            fail("음성 엔진을 찾지 못했어요", log: "engine.py missing from the app bundle")
            return
        }

        let process = Process()
        process.executableURL = AppPaths.python
        process.arguments = ["-u", script.path]
        process.qualityOfService = .userInitiated
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONUNBUFFERED"] = "1"
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        environment["HF_HUB_DISABLE_TELEMETRY"] = "1"
        environment["HF_HUB_DISABLE_PROGRESS_BARS"] = "1"
        environment["TOKENIZERS_PARALLELISM"] = "false"
        process.environment = environment

        let stdin = Pipe()
        let stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = Log.engineOutput()
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            DispatchQueue.main.async { self?.receive(data) }
        }
        process.terminationHandler = { [weak self] exited in
            DispatchQueue.main.async { self?.handleExit(of: exited) }
        }

        do {
            try process.run()
        } catch {
            fail("음성 엔진을 시작하지 못했어요", log: "engine launch: \(error.localizedDescription)")
            return
        }
        self.process = process
        input = stdin.fileHandleForWriting
        output.removeAll()
        status = .starting
    }

    private func install() {
        isInstalling = true
        status = .installing
        Log.info("installing the speech engine")
        Task { @MainActor in
            do {
                try await EngineInstaller.install()
                isInstalling = false
                start()
            } catch {
                isInstalling = false
                fail("음성 엔진을 설치하지 못했어요", log: "engine install: \(error.localizedDescription)")
            }
        }
    }

    func stop() {
        isStopping = true
        try? input?.close()
        process?.terminate()
        process = nil
        input = nil
    }

    func restart() {
        stop()
        recentExits.removeAll()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.start() }
    }

    // MARK: Requests

    /// Transcribes 16 kHz mono audio. `context` (names, nearby text) biases spelling.
    /// Completion runs on the main queue.
    func transcribe(_ samples: [Float], context: String, completion: @escaping Completion) {
        if case let .failed(message) = status, process == nil {
            completion(.failure(Failure.unavailable(message)))
            return
        }
        let id = nextRequestID
        nextRequestID += 1
        let audio = samples.withUnsafeBufferPointer { Data(buffer: $0) }
        let fields: [String: Any] = ["id": id, "op": "transcribe", "bytes": audio.count, "context": context]
        guard var header = try? JSONSerialization.data(withJSONObject: fields) else {
            completion(.failure(Failure.recognition))
            return
        }
        header.append(0x0A)
        waiting[id] = completion
        if status.isReady {
            send(header: header, audio: audio)
        } else {
            queued.append((id, header, audio))
        }
    }

    private func send(header: Data, audio: Data) {
        guard let input else { return }
        writer.async {
            do {
                try input.write(contentsOf: header)
                try input.write(contentsOf: audio)
            } catch {
                Log.info("engine write: \(error.localizedDescription)")
            }
        }
    }

    // MARK: Replies

    private func receive(_ data: Data) {
        guard !data.isEmpty else { return }
        output.append(data)
        while let newline = output.firstIndex(of: 0x0A) {
            let line = output[output.startIndex..<newline]
            output.removeSubrange(output.startIndex...newline)
            if let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any] {
                handle(message)
            }
        }
    }

    private func handle(_ message: [String: Any]) {
        if let event = message["event"] as? String {
            switch event {
            case "loading":
                status = .starting
            case "downloading":
                status = .downloading
            case "ready":
                status = .ready
                Log.info("engine ready in \(message["load_ms"] ?? "?") ms")
                let pending = queued
                queued.removeAll()
                for request in pending where waiting[request.id] != nil {
                    send(header: request.header, audio: request.audio)
                }
            case "failed":
                fail("음성 모델을 불러오지 못했어요", log: "engine failed: \(message["error"] ?? "?")")
            default:
                break
            }
            return
        }
        guard let id = message["id"] as? Int, let completion = waiting.removeValue(forKey: id) else { return }
        if let text = message["text"] as? String {
            Log.info("asr \(message["audio_ms"] ?? "?") ms audio → \(message["ms"] ?? "?") ms, \(text.count) chars")
            completion(.success(text))
        } else {
            Log.info("asr error: \(message["error"] ?? "?")")
            completion(.failure(Failure.recognition))
        }
    }

    private func handleExit(of exited: Process) {
        guard exited === process || process == nil else { return }
        (exited.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        process = nil
        input = nil
        Log.info("engine exited (\(exited.terminationStatus))")
        failWaiting(Failure.unavailable("음성 엔진이 멈췄어요"))
        guard !isStopping else { return }

        // Restart after a crash, but give up if it keeps crashing.
        let now = Date()
        recentExits = recentExits.filter { now.timeIntervalSince($0) < 120 } + [now]
        if recentExits.count <= 3 {
            status = .starting
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.start() }
        } else if !isFailed {
            status = .failed("음성 엔진이 계속 멈춰요")
        }
    }

    private var isFailed: Bool {
        if case .failed = status { return true }
        return false
    }

    private func fail(_ message: String, log: String) {
        status = .failed(message)
        Log.info(log)
        failWaiting(Failure.unavailable(message))
    }

    private func failWaiting(_ error: Error) {
        let pending = waiting
        waiting.removeAll()
        queued.removeAll()
        pending.values.forEach { $0(.failure(error)) }
    }
}
