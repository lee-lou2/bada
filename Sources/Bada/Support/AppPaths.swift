import Foundation

/// Where bada keeps files. Nothing is written next to the app, so it can live anywhere.
enum AppPaths {
    private static let home = FileManager.default.homeDirectoryForCurrentUser

    static let support = home.appendingPathComponent("Library/Application Support/Bada", isDirectory: true)
    static let caches = home.appendingPathComponent("Library/Caches/Bada", isDirectory: true)
    static let logs = home.appendingPathComponent("Library/Logs/Bada", isDirectory: true)

    /// uv, its Python, and the speech engine's environment. Set up by `EngineInstaller`.
    static let engine = support.appendingPathComponent("engine", isDirectory: true)
    static let engineEnvironment = engine.appendingPathComponent("venv", isDirectory: true)
    static let python = engineEnvironment.appendingPathComponent("bin/python3")

    /// The LLM API key. Readable by this macOS user only.
    static let apiKey = support.appendingPathComponent("api-key")
}
