import Foundation

/// Stores the LLM API key in a file only this macOS user can read (mode 0600).
///
/// Not the Keychain on purpose: an app built without a Developer ID has no stable identity for
/// the Keychain to trust, so every rebuild would stop and ask for the login password.
enum APIKeyStore {
    static func read() -> String {
        guard let data = try? Data(contentsOf: AppPaths.apiKey) else { return "" }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func write(_ key: String) {
        let manager = FileManager.default
        guard !key.isEmpty else {
            try? manager.removeItem(at: AppPaths.apiKey)
            return
        }
        try? manager.createDirectory(at: AppPaths.support, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        manager.createFile(atPath: AppPaths.apiKey.path, contents: Data(key.utf8), attributes: [.posixPermissions: 0o600])
        try? manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: AppPaths.apiKey.path)
    }
}
