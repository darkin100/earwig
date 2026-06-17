import Foundation

struct Config: Codable {
    private static let defaultEnableDiarization = true
    private static let defaultKeepSpeakerEmbeddings = true
    private static let defaultClusteringThreshold = 0.7
    private static let defaultMinSpeechDuration = 1.0
    private static let defaultVoiceMatchThreshold = 0.6
    private static let defaultClusterMergeThreshold = 0.7
    private static let defaultMaxSamplesPerVoice = 5
    private static let defaultMinSpeakerSeconds = 5.0
    private static let defaultHasCompletedOnboarding = false
    private static let defaultAutoSummarize = true
    private static let defaultSummaryTemplateID = "daily-standup"
    private static let defaultCustomSummaryInstructions = ""
    private static let defaultSummaryEngine = "ollama"
    private static let defaultSummaryModelID = "qwen2.5:14b"
    private static let defaultSummaryClaudeModel = "claude-sonnet-4-6"

    var notesFolder: String
    var audioFolder: String
    var keepAudio: Bool
    var localeIdentifier: String
    var enableDiarization: Bool
    var keepSpeakerEmbeddings: Bool
    var clusteringThreshold: Double
    var minSpeechDuration: Double
    var voiceMatchThreshold: Double
    var clusterMergeThreshold: Double
    var maxSamplesPerVoice: Int
    var minSpeakerSeconds: Double
    var hasCompletedOnboarding: Bool
    var autoSummarize: Bool
    var summaryTemplateID: String
    var customSummaryInstructions: String
    var summaryEngine: String  // "ollama" | "apple" | "claude"
    var summaryModelID: String // Ollama tag, e.g. "qwen2.5:14b"
    var summaryClaudeModel: String // Claude model ID

    init(
        notesFolder: String, audioFolder: String, keepAudio: Bool, localeIdentifier: String,
        enableDiarization: Bool = Config.defaultEnableDiarization,
        keepSpeakerEmbeddings: Bool = Config.defaultKeepSpeakerEmbeddings,
        clusteringThreshold: Double = Config.defaultClusteringThreshold,
        minSpeechDuration: Double = Config.defaultMinSpeechDuration,
        voiceMatchThreshold: Double = Config.defaultVoiceMatchThreshold,
        clusterMergeThreshold: Double = Config.defaultClusterMergeThreshold,
        maxSamplesPerVoice: Int = Config.defaultMaxSamplesPerVoice,
        minSpeakerSeconds: Double = Config.defaultMinSpeakerSeconds,
        hasCompletedOnboarding: Bool = Config.defaultHasCompletedOnboarding,
        autoSummarize: Bool = Config.defaultAutoSummarize,
        summaryTemplateID: String = Config.defaultSummaryTemplateID,
        customSummaryInstructions: String = Config.defaultCustomSummaryInstructions,
        summaryEngine: String = Config.defaultSummaryEngine,
        summaryModelID: String = Config.defaultSummaryModelID,
        summaryClaudeModel: String = Config.defaultSummaryClaudeModel
    ) {
        self.notesFolder = notesFolder
        self.audioFolder = audioFolder
        self.keepAudio = keepAudio
        self.localeIdentifier = localeIdentifier
        self.enableDiarization = enableDiarization
        self.keepSpeakerEmbeddings = keepSpeakerEmbeddings
        self.clusteringThreshold = clusteringThreshold
        self.minSpeechDuration = minSpeechDuration
        self.voiceMatchThreshold = voiceMatchThreshold
        self.clusterMergeThreshold = clusterMergeThreshold
        self.maxSamplesPerVoice = maxSamplesPerVoice
        self.minSpeakerSeconds = minSpeakerSeconds
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.autoSummarize = autoSummarize
        self.summaryTemplateID = summaryTemplateID
        self.customSummaryInstructions = customSummaryInstructions
        self.summaryEngine = summaryEngine
        self.summaryModelID = summaryModelID
        self.summaryClaudeModel = summaryClaudeModel
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        notesFolder = try c.decode(String.self, forKey: .notesFolder)
        audioFolder = try c.decode(String.self, forKey: .audioFolder)
        keepAudio = try c.decode(Bool.self, forKey: .keepAudio)
        localeIdentifier = try c.decode(String.self, forKey: .localeIdentifier)
        enableDiarization = try c.decodeIfPresent(Bool.self, forKey: .enableDiarization) ?? Config.defaultEnableDiarization
        keepSpeakerEmbeddings = try c.decodeIfPresent(Bool.self, forKey: .keepSpeakerEmbeddings) ?? Config.defaultKeepSpeakerEmbeddings
        clusteringThreshold = try c.decodeIfPresent(Double.self, forKey: .clusteringThreshold) ?? Config.defaultClusteringThreshold
        minSpeechDuration = try c.decodeIfPresent(Double.self, forKey: .minSpeechDuration) ?? Config.defaultMinSpeechDuration
        voiceMatchThreshold = try c.decodeIfPresent(Double.self, forKey: .voiceMatchThreshold) ?? Config.defaultVoiceMatchThreshold
        clusterMergeThreshold = try c.decodeIfPresent(Double.self, forKey: .clusterMergeThreshold) ?? Config.defaultClusterMergeThreshold
        maxSamplesPerVoice = try c.decodeIfPresent(Int.self, forKey: .maxSamplesPerVoice) ?? Config.defaultMaxSamplesPerVoice
        minSpeakerSeconds = try c.decodeIfPresent(Double.self, forKey: .minSpeakerSeconds) ?? Config.defaultMinSpeakerSeconds
        hasCompletedOnboarding = try c.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? Config.defaultHasCompletedOnboarding
        autoSummarize = try c.decodeIfPresent(Bool.self, forKey: .autoSummarize) ?? Config.defaultAutoSummarize
        summaryTemplateID = try c.decodeIfPresent(String.self, forKey: .summaryTemplateID) ?? Config.defaultSummaryTemplateID
        customSummaryInstructions = try c.decodeIfPresent(String.self, forKey: .customSummaryInstructions) ?? Config.defaultCustomSummaryInstructions
        summaryEngine = try c.decodeIfPresent(String.self, forKey: .summaryEngine) ?? Config.defaultSummaryEngine
        summaryModelID = try c.decodeIfPresent(String.self, forKey: .summaryModelID) ?? Config.defaultSummaryModelID
        summaryClaudeModel = try c.decodeIfPresent(String.self, forKey: .summaryClaudeModel) ?? Config.defaultSummaryClaudeModel
    }

    static var defaultConfig: Config {
        Config(
            notesFolder: ("~/MeetingNotes" as NSString).expandingTildeInPath,
            audioFolder: ("~/MeetingNotes/audio" as NSString).expandingTildeInPath,
            keepAudio: true,
            localeIdentifier: Locale.current.identifier
        )
    }

    static var configURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Earwig", isDirectory: true)
        return dir.appendingPathComponent("config.json")
    }

    static var voicesURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Earwig", isDirectory: true)
        return dir.appendingPathComponent("voices.json")
    }

    static func load() -> Config {
        let url = configURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            let cfg = defaultConfig
            cfg.save()
            return cfg
        }
        do {
            return try JSONDecoder().decode(Config.self, from: Data(contentsOf: url))
        } catch {
            // Don't overwrite a corrupt file — that would lose the user's notesFolder/locale.
            Log.info("config.json is unreadable (\(error)); using defaults without overwriting it")
            return defaultConfig
        }
    }

    func save() {
        let url = Config.configURL
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(self).write(to: url)
        } catch {
            Log.info("Failed to save config.json: \(error)")
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
    // Serialise concurrent writes from background pipeline and diarizer.
    private static let queue = DispatchQueue(label: "io.earwig.log")

    static let logURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Earwig", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("earwig.log")
    }()

    /// True under XCTest — prevents test runs from writing to the real log.
    private static let isTesting =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    static func info(_ message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(stamp)] \(message)\n"
        queue.sync {
            print(line, terminator: "")
            if isTesting { return }   // don't write the production log from unit tests
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
}
