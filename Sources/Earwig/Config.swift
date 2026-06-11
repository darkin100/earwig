import Foundation

struct Config: Codable {
    var notesFolder: String
    var audioFolder: String
    var keepAudio: Bool
    var localeIdentifier: String

    static var defaultConfig: Config {
        Config(
            notesFolder: ("~/MeetingNotes" as NSString).expandingTildeInPath,
            audioFolder: ("~/MeetingNotes/audio" as NSString).expandingTildeInPath,
            keepAudio: true,
            localeIdentifier: "en_GB"
        )
    }

    static var configURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Earwig", isDirectory: true)
        return dir.appendingPathComponent("config.json")
    }

    static func load() -> Config {
        let url = configURL
        if let data = try? Data(contentsOf: url),
           let cfg = try? JSONDecoder().decode(Config.self, from: data) {
            return cfg
        }
        let cfg = defaultConfig
        cfg.save()
        return cfg
    }

    func save() {
        let url = Config.configURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(self) {
            try? data.write(to: url)
        }
    }

    var notesFolderURL: URL { URL(fileURLWithPath: (notesFolder as NSString).expandingTildeInPath) }
    var audioFolderURL: URL { URL(fileURLWithPath: (audioFolder as NSString).expandingTildeInPath) }

    func ensureFolders() {
        try? FileManager.default.createDirectory(at: notesFolderURL, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: audioFolderURL, withIntermediateDirectories: true)
    }
}

enum Log {
    static let logURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Earwig", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("earwig.log")
    }()

    static func info(_ message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(stamp)] \(message)\n"
        print(line, terminator: "")
        if let data = line.data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: logURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: logURL)
            }
        }
    }
}
