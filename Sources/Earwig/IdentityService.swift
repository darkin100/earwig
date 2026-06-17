import Foundation

/// Enroll and name speakers. Side effects go through explicit URLs for testability.
enum IdentityService {
    enum ServiceError: Error, LocalizedError {
        case noSpeakers(String)
        case labelNotFound(String)
        case noEmbedding(String)
        case invalidName(String)

        var errorDescription: String? {
            switch self {
            case .noSpeakers(let meeting): return "No speakers.json for \(meeting) — re-run --process first"
            case .labelNotFound(let label): return "Speaker '\(label)' not found in that meeting"
            case .noEmbedding(let label): return "Speaker '\(label)' has no voiceprint to enroll"
            case .invalidName(let why): return "Invalid speaker name: \(why)"
            }
        }
    }

    /// Enrolls the voiceprint of `label` in `meeting` under the reserved "Me" identity, and
    /// relabels that meeting's speaker to "Me" so the change is visible immediately.
    @discardableResult
    static func enrollMe(meeting: String, label: String,
                         notesFolder: URL, voicesURL: URL, maxSamples: Int) throws -> Bool {
        try enroll(meeting: meeting, label: label, as: "Me", isMe: true,
                   notesFolder: notesFolder, voicesURL: voicesURL, maxSamples: maxSamples,
                   relabel: true)
    }

    /// Enrolls `label`'s voiceprint under `name` and relabels that meeting's note + transcript.
    /// Returns `true` if the note was re-rendered, `false` if enrolled but no transcript.json existed.
    @discardableResult
    static func nameSpeaker(meeting: String, label: String, name: String,
                            notesFolder: URL, voicesURL: URL, maxSamples: Int) throws -> Bool {
        try validate(name: name)
        return try enroll(meeting: meeting, label: label, as: name, isMe: false,
                          notesFolder: notesFolder, voicesURL: voicesURL, maxSamples: maxSamples,
                          relabel: true)
    }

    static func listIdentities(voicesURL: URL) throws -> [VoiceIdentity] {
        try VoiceRegistry.load(from: voicesURL).identities
    }

    static func forget(_ name: String, voicesURL: URL) throws {
        var reg = try VoiceRegistry.load(from: voicesURL)
        reg.forget(name)
        try reg.save(to: voicesURL)
    }

    // MARK: - internals

    /// Rejects empty names, frontmatter-unsafe characters, and reserved labels.
    private static func validate(name: String) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ServiceError.invalidName("name cannot be empty")
        }
        guard !name.contains(where: { "\n\r,[]".contains($0) }) else {
            throw ServiceError.invalidName("name cannot contain a newline, comma, or square bracket")
        }
        guard case .named = SpeakerLabel.parse(name) else {
            throw ServiceError.invalidName("'\(name)' is a reserved label")
        }
    }

    private static func enroll(meeting: String, label: String, as name: String, isMe: Bool,
                               notesFolder: URL, voicesURL: URL, maxSamples: Int,
                               relabel: Bool) throws -> Bool {
        let stem = meetingStem(meeting)
        let speakersURL = notesFolder.appendingPathComponent("\(stem).speakers.json")
        guard FileManager.default.fileExists(atPath: speakersURL.path) else {
            throw ServiceError.noSpeakers(stem)
        }
        let profiles = try SpeakerStore.read(from: speakersURL)
        guard let profile = profiles.first(where: { $0.label.displayName == label }) else {
            throw ServiceError.labelNotFound(label)
        }
        guard let embedding = profile.embedding else { throw ServiceError.noEmbedding(label) }

        let target: SpeakerLabel = isMe ? .me : .named(name)
        // Re-render before committing the registry: idempotent, so a failed save can be retried.
        let relabeled = relabel
            ? try relabelNote(stem: stem, from: label, to: target, notesFolder: notesFolder)
            : false

        var reg = try VoiceRegistry.load(from: voicesURL)
        reg.enroll(name: name, embedding: embedding, isMe: isMe, maxSamples: maxSamples)
        try reg.save(to: voicesURL)
        Log.info("Enrolled '\(name)' from \(stem)/\(label)")
        return relabeled
    }

    /// Rewrites transcript.json and re-renders the note, remapping `from` to `toLabel`.
    @discardableResult
    private static func relabelNote(stem: String, from: String, to toLabel: SpeakerLabel,
                                    notesFolder: URL) throws -> Bool {
        let recordURL = notesFolder.appendingPathComponent("\(stem).transcript.json")
        guard FileManager.default.fileExists(atPath: recordURL.path) else {
            Log.info("No transcript.json for \(stem); enrolled but note not re-rendered")
            return false
        }
        let record = try MeetingRecord.read(from: recordURL)
        let fromLabel = SpeakerLabel.parse(from)
        let newTurns = record.turns.map { turn in
            turn.speaker == fromLabel
                ? TranscriptSegment(speaker: toLabel, start: turn.start, end: turn.end, text: turn.text)
                : turn
        }
        let updated = MeetingRecord(
            meeting: record.meeting, date: record.date, durationSeconds: record.durationSeconds,
            source: record.source, mode: record.mode, turns: newTurns)
        try updated.write(to: recordURL)

        var seen: [SpeakerLabel] = []
        for t in newTurns where !seen.contains(t.speaker) { seen.append(t.speaker) }
        let md = TranscriptNote.markdown(
            turns: newTurns, speakers: seen, mode: record.mode,
            meetingDate: Date(timeIntervalSince1970: record.date),
            duration: record.durationSeconds,
            apps: record.source == "manual recording" ? [] : [record.source])
        try md.write(to: notesFolder.appendingPathComponent("\(stem).md"),
                     atomically: true, encoding: .utf8)
        return true
    }

    /// Normalises a stem, filename, or path to the bare meeting stem.
    private static func meetingStem(_ meeting: String) -> String {
        let base = (meeting as NSString).lastPathComponent
        for suffix in [".md", ".speakers.json", ".transcript.json"] {
            if base.hasSuffix(suffix) { return String(base.dropLast(suffix.count)) }
        }
        return base
    }
}
