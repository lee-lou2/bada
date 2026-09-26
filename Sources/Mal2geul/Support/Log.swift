import Foundation

/// Plain-text log in `~/Library/Logs/Mal2geul`. Sizes and timings only, never what was said.
enum Log {
    private static let file = AppPaths.logs.appendingPathComponent("mal2geul.log")
    private static let queue = DispatchQueue(label: "app.mal2geul.log")
    private static let maxBytes = 1_000_000
    private static let timestamp: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func info(_ message: String) {
        let line = "\(timestamp.string(from: Date())) \(message)\n"
        queue.async { append(line) }
    }

    /// Where the speech engine and its installer write their output: `engine.log`.
    static func engineOutput() -> FileHandle {
        let manager = FileManager.default
        let url = AppPaths.logs.appendingPathComponent("engine.log")
        try? manager.createDirectory(at: AppPaths.logs, withIntermediateDirectories: true)
        if let size = (try? manager.attributesOfItem(atPath: url.path))?[.size] as? Int, size > 2 * maxBytes {
            try? manager.removeItem(at: url)
        }
        if !manager.fileExists(atPath: url.path) { manager.createFile(atPath: url.path, contents: nil) }
        guard let handle = try? FileHandle(forWritingTo: url) else { return .nullDevice }
        _ = try? handle.seekToEnd()
        return handle
    }

    private static func append(_ line: String) {
        let manager = FileManager.default
        try? manager.createDirectory(at: AppPaths.logs, withIntermediateDirectories: true)
        if let size = (try? manager.attributesOfItem(atPath: file.path))?[.size] as? Int, size > maxBytes {
            let previous = AppPaths.logs.appendingPathComponent("mal2geul.1.log")
            try? manager.removeItem(at: previous)
            try? manager.moveItem(at: file, to: previous)
        }
        guard let handle = try? FileHandle(forWritingTo: file) else {
            try? Data(line.utf8).write(to: file)
            return
        }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        handle.write(Data(line.utf8))
    }
}
