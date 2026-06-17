import Foundation

/// Structured, re-renderable transcript persisted next to each note as
/// `meeting-<stamp>.transcript.json`. Lets naming remap labels and re-render the note,
/// and gives a future UI structured data to display/edit.
struct MeetingRecord {
    let meeting: String
    let date: TimeInterval          // seconds since 1970, for faithful re-render
    let durationSeconds: TimeInterval
    let source: String              // apps joined, or "manual recording"
    let mode: DiarizationMode
    let turns: [TranscriptSegment]

    private struct Turn: Codable {
        let label: SpeakerLabel
        let start: TimeInterval
        let end: TimeInterval
        let text: String
    }
    private struct Document: Codable {
        let meeting: String
        let date: TimeInterval
        let durationSeconds: TimeInterval
        let source: String
        let mode: String
        let turns: [Turn]
    }

    func write(to url: URL) throws {
        let doc = Document(
            meeting: meeting, date: date, durationSeconds: durationSeconds,
            source: source, mode: mode.rawValue,
            turns: turns.map { Turn(label: $0.speaker, start: $0.start, end: $0.end, text: $0.text) })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(doc).write(to: url, options: .atomic)
    }

    static func read(from url: URL) throws -> MeetingRecord {
        let doc = try JSONDecoder().decode(Document.self, from: Data(contentsOf: url))
        let mode = DiarizationMode(rawValue: doc.mode)
        if mode == nil {
            Log.info("Unknown diarization mode '\(doc.mode)' in \(url.lastPathComponent); defaulting to full")
        }
        return MeetingRecord(
            meeting: doc.meeting, date: doc.date, durationSeconds: doc.durationSeconds,
            source: doc.source, mode: mode ?? .full,
            turns: doc.turns.map {
                TranscriptSegment(speaker: $0.label, start: $0.start, end: $0.end, text: $0.text)
            })
    }
}
