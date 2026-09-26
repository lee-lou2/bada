import Foundation

/// Plain-text log in `~/Library/Logs/Bada`. Sizes and timings only, never what was said.
enum Log {
    private static let file = AppPaths.logs.appendingPathComponent("bada.log")
    private static let queue = DispatchQueue(label: "app.bada.log")
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

    private static func append(_ line: String) {
        let manager = FileManager.default
        try? manager.createDirectory(at: AppPaths.logs, withIntermediateDirectories: true)
        if let size = (try? manager.attributesOfItem(atPath: file.path))?[.size] as? Int, size > maxBytes {
            let previous = AppPaths.logs.appendingPathComponent("bada.1.log")
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
