import CryptoKit
import Foundation

/// Sets up the Python environment the speech engine runs in, on first launch and whenever an update
/// changes the locked dependencies.
///
/// uv is downloaded from its official release and checked against a pinned SHA-256. uv then installs
/// its own Python and the hash-locked packages from `requirements.txt`. Everything lives in
/// `~/Library/Application Support/Mal2geul/engine`; nothing touches the system Python.
enum EngineInstaller {
    enum Failure: LocalizedError {
        case missingRequirements
        case download
        case checksumMismatch
        case command(String, Int32)

        var errorDescription: String? {
            switch self {
            case .missingRequirements: return "requirements.txt is missing from the app"
            case .download: return "could not download uv"
            case .checksumMismatch: return "uv download failed its checksum"
            case let .command(name, status): return "\(name) exited with \(status)"
            }
        }
    }

    private static let uvVersion = "0.11.2"
    private static let uvArchive = URL(string: "https://github.com/astral-sh/uv/releases/download/\(uvVersion)/uv-aarch64-apple-darwin.tar.gz")!
    private static let uvArchiveSHA256 = "4beaa9550f93ef7f0fc02f7c28c9c48cd61fe30db00f5ac8947e0a425c3fb282"
    private static let pythonVersion = "3.12"

    private static let uv = AppPaths.engine.appendingPathComponent("uv-\(uvVersion)")
    /// Records which lock file the environment was built from.
    private static let stamp = AppPaths.engineEnvironment.appendingPathComponent(".requirements-sha256")
    private static let requirements = Bundle.main.url(forResource: "requirements", withExtension: "txt")

    /// The environment exists and was built from the lock file bundled with this version.
    static var isInstalled: Bool {
        guard FileManager.default.isExecutableFile(atPath: AppPaths.python.path),
              let requirements, let wanted = try? sha256(of: Data(contentsOf: requirements)),
              let built = try? String(contentsOf: stamp, encoding: .utf8) else { return false }
        return built == wanted
    }

    static func install() async throws {
        guard let requirements else { throw Failure.missingRequirements }
        let started = Date()
        let uv = try await downloadUV()
        let environment = [
            "UV_PYTHON_INSTALL_DIR": AppPaths.engine.appendingPathComponent("python").path,
            "UV_CACHE_DIR": AppPaths.caches.appendingPathComponent("uv").path,
            "UV_NO_CONFIG": "1",
            "UV_NO_PROGRESS": "1",
        ]
        try? FileManager.default.removeItem(at: AppPaths.engineEnvironment)
        try await run(uv, ["venv", "--python", pythonVersion, "--python-preference", "only-managed", AppPaths.engineEnvironment.path], environment: environment)
        try await run(uv, ["pip", "install", "--python", AppPaths.python.path, "--require-hashes", "-r", requirements.path], environment: environment)
        try sha256(of: Data(contentsOf: requirements)).write(to: stamp, atomically: true, encoding: .utf8)
        // The downloaded archives are no longer needed once installed.
        try? FileManager.default.removeItem(at: AppPaths.caches.appendingPathComponent("uv"))
        Log.info(String(format: "engine installed in %.0fs", Date().timeIntervalSince(started)))
    }

    private static func downloadUV() async throws -> URL {
        let manager = FileManager.default
        if manager.isExecutableFile(atPath: uv.path) { return uv }

        let (archive, response) = try await URLSession.shared.download(from: uvArchive)
        defer { try? manager.removeItem(at: archive) }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure.download }
        guard try sha256(of: Data(contentsOf: archive)) == uvArchiveSHA256 else { throw Failure.checksumMismatch }

        let unpacked = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: unpacked, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: unpacked) }
        try await run(URL(fileURLWithPath: "/usr/bin/tar"), ["-xzf", archive.path, "-C", unpacked.path])
        try manager.createDirectory(at: AppPaths.engine, withIntermediateDirectories: true)
        try? manager.removeItem(at: uv)
        try manager.moveItem(at: unpacked.appendingPathComponent("uv-aarch64-apple-darwin/uv"), to: uv)
        return uv
    }

    /// Runs a command to completion, output going to engine.log.
    private static func run(_ tool: URL, _ arguments: [String], environment: [String: String] = [:]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = tool
            process.arguments = arguments
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
            let log = Log.engineOutput()
            process.standardOutput = log
            process.standardError = log
            process.terminationHandler = { finished in
                if finished.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: Failure.command(tool.lastPathComponent, finished.terminationStatus))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private static func sha256(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
