import Foundation

/// A transcribed span of speech with its time range (seconds from recording start).
struct TimedSegment: Equatable {
    let text: String
    let start: TimeInterval
    let end: TimeInterval

    init(text: String, start: TimeInterval, end: TimeInterval) {
        self.text = text
        self.start = start
        self.end = max(start, end)
    }
}

/// Who is speaking. `remote` cluster ids are 1-based; `named` is an enrolled person.
/// Persisted via the tagged `Codable` form below — not `displayName`, which would alias a
/// person named "Others"/"Speaker 3" onto the wrong case.
enum SpeakerLabel: Equatable, Codable {
    case me
    case named(String)
    case remote(Int)
    case others

    var displayName: String {
        switch self {
        case .me: return "Me"
        case .named(let n): return n
        case .remote(let n): return "Speaker \(n)"
        case .others: return "Others"
        }
    }

    /// Parses human-typed labels. Persistence uses `Codable`, not this.
    static func parse(_ s: String) -> SpeakerLabel {
        if s == "Me" { return .me }
        if s == "Others" { return .others }
        if s.hasPrefix("Speaker "), let n = Int(s.dropFirst("Speaker ".count)) { return .remote(n) }
        return .named(s)
    }

    private enum CodingKeys: String, CodingKey { case kind, name, id }
    private enum Kind: String, Codable { case me, named, remote, others }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .me: try c.encode(Kind.me, forKey: .kind)
        case .others: try c.encode(Kind.others, forKey: .kind)
        case .named(let n): try c.encode(Kind.named, forKey: .kind); try c.encode(n, forKey: .name)
        case .remote(let id): try c.encode(Kind.remote, forKey: .kind); try c.encode(id, forKey: .id)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .me: self = .me
        case .others: self = .others
        case .named: self = .named(try c.decode(String.self, forKey: .name))
        case .remote: self = .remote(try c.decode(Int.self, forKey: .id))
        }
    }
}

/// A diarization cluster occupying a time range (seconds). `clusterId` is 1-based.
struct SpeakerSegment: Equatable {
    let clusterId: Int
    let start: TimeInterval
    let end: TimeInterval

    init(clusterId: Int, start: TimeInterval, end: TimeInterval) {
        self.clusterId = clusterId
        self.start = start
        self.end = max(start, end)
    }
}

/// A transcript turn attributed to a speaker.
struct TranscriptSegment: Equatable {
    let speaker: SpeakerLabel
    let start: TimeInterval
    let end: TimeInterval
    let text: String

    init(speaker: SpeakerLabel, start: TimeInterval, end: TimeInterval, text: String) {
        self.speaker = speaker
        self.start = start
        self.end = max(start, end)
        self.text = text
    }
}

/// A speaker's persisted voiceprint and total speech time.
struct SpeakerProfile: Equatable {
    let label: SpeakerLabel
    let embedding: [Float]?
    let speechSeconds: TimeInterval
}

/// Which transcription mode actually produced the note (written to frontmatter).
enum DiarizationMode: String {
    case full
    case meVsOthers = "me-vs-others"
    case none
}
