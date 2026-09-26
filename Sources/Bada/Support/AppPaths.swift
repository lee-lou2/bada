import Foundation

/// Where bada keeps files. Nothing is written next to the app, so it can live anywhere.
enum AppPaths {
    private static let home = FileManager.default.homeDirectoryForCurrentUser

    static let support = home.appendingPathComponent("Library/Application Support/Bada", isDirectory: true)
    static let logs = home.appendingPathComponent("Library/Logs/Bada", isDirectory: true)

    /// Python environment for the speech engine, created by `scripts/build.sh`.
    static let python = support.appendingPathComponent("python/bin/python3")
    /// The LLM API key. Readable by this macOS user only.
    static let apiKey = support.appendingPathComponent("api-key")
}
