import Foundation

/// Persists per-speaker voiceprints as JSON beside the transcript note.
enum SpeakerStore {
    private struct Entry: Codable {
        let label: SpeakerLabel
        let speechSeconds: TimeInterval
        let embedding: [Float]?
    }

    private struct Document: Codable {
        let meeting: String
        let speakers: [Entry]
    }

    static func write(_ profiles: [SpeakerProfile], meeting: String, to url: URL) throws {
        let doc = Document(
            meeting: meeting,
            speakers: profiles.map {
                Entry(label: $0.label, speechSeconds: $0.speechSeconds, embedding: $0.embedding)
            })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(doc)
        try data.write(to: url, options: .atomic)
    }

    static func read(from url: URL) throws -> [SpeakerProfile] {
        let data = try Data(contentsOf: url)
        let doc = try JSONDecoder().decode(Document.self, from: data)
        return doc.speakers.map { entry in
            SpeakerProfile(
                label: entry.label,
                embedding: entry.embedding,
                speechSeconds: entry.speechSeconds)
        }
    }
}
