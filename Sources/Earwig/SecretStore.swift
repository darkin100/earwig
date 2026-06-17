import Foundation

/// File-based secret store (Application Support/Earwig/secrets, 0600).
/// Keychain access is tied to code signature — lost on every re-sign — so files are used instead.
enum SecretStore {
    private static var directory: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Earwig/secrets", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return dir
    }

    static func get(_ key: String) -> String? {
        let url = directory.appendingPathComponent(key)
        guard let data = try? Data(contentsOf: url),
              let value = String(data: data, encoding: .utf8), !value.isEmpty else { return nil }
        return value
    }

    static func set(_ value: String, for key: String) {
        let url = directory.appendingPathComponent(key)
        if value.isEmpty {
            try? FileManager.default.removeItem(at: url)
            return
        }
        try? Data(value.utf8).write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func delete(_ key: String) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(key))
    }

    static var anthropicKey: String? {
        get { get("anthropic-api-key") }
        set { set(newValue ?? "", for: "anthropic-api-key") }
    }
}
