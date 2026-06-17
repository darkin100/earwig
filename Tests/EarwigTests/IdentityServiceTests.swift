import XCTest
@testable import Earwig

final class IdentityServiceTests: XCTestCase {
    /// Builds a temp notes dir with a speakers.json + transcript.json for "meeting-x".
    private func fixture() throws -> (dir: URL, voices: URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("earwig-id-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let speakers = [
            SpeakerProfile(label: .me, embedding: nil, speechSeconds: 10),
            SpeakerProfile(label: .remote(1), embedding: [0, 1], speechSeconds: 20),
        ]
        try SpeakerStore.write(speakers, meeting: "meeting-x",
                               to: dir.appendingPathComponent("meeting-x.speakers.json"))
        let turns = [
            TranscriptSegment(speaker: .me, start: 0, end: 2, text: "Hi"),
            TranscriptSegment(speaker: .remote(1), start: 2, end: 6, text: "Hello there"),
        ]
        try MeetingRecord(meeting: "meeting-x", date: 1_000_000, durationSeconds: 6,
                          source: "manual recording", mode: .full, turns: turns)
            .write(to: dir.appendingPathComponent("meeting-x.transcript.json"))
        try "placeholder".write(to: dir.appendingPathComponent("meeting-x.md"), atomically: true, encoding: .utf8)
        return (dir, dir.appendingPathComponent("voices.json"))
    }

    func testNameSpeakerEnrollsAndRelabels() throws {
        let (dir, voices) = try fixture()
        defer { try? FileManager.default.removeItem(at: dir) }

        try IdentityService.nameSpeaker(
            meeting: "meeting-x", label: "Speaker 1", name: "Cecile",
            notesFolder: dir, voicesURL: voices, maxSamples: 5)

        let reg = try VoiceRegistry.load(from: voices)
        XCTAssertEqual(reg.match([0, 1], threshold: 0.9)?.identity.name, "Cecile")

        let rec = try MeetingRecord.read(from: dir.appendingPathComponent("meeting-x.transcript.json"))
        XCTAssertEqual(rec.turns.map(\.speaker), [.me, .named("Cecile")])
        let note = try String(contentsOf: dir.appendingPathComponent("meeting-x.md"), encoding: .utf8)
        XCTAssertTrue(note.contains("**Cecile**"))
        XCTAssertFalse(note.contains("Speaker 1"))
    }

    func testEnrollMeStoresIsMe() throws {
        let (dir, voices) = try fixture()
        defer { try? FileManager.default.removeItem(at: dir) }
        try IdentityService.enrollMe(
            meeting: "meeting-x", label: "Speaker 1",
            notesFolder: dir, voicesURL: voices, maxSamples: 5)
        let reg = try VoiceRegistry.load(from: voices)
        XCTAssertTrue(reg.identities.contains { $0.isMe })

        // "This is me" also relabels the meeting's speaker to .me so the change is visible.
        let rec = try MeetingRecord.read(from: dir.appendingPathComponent("meeting-x.transcript.json"))
        XCTAssertEqual(rec.turns.map(\.speaker), [.me, .me])
    }

    func testUnknownLabelThrows() throws {
        let (dir, voices) = try fixture()
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertThrowsError(try IdentityService.nameSpeaker(
            meeting: "meeting-x", label: "Speaker 9", name: "Ghost",
            notesFolder: dir, voicesURL: voices, maxSamples: 5))
    }

    func testForget() throws {
        let (dir, voices) = try fixture()
        defer { try? FileManager.default.removeItem(at: dir) }
        try IdentityService.nameSpeaker(meeting: "meeting-x", label: "Speaker 1", name: "Cecile",
                                        notesFolder: dir, voicesURL: voices, maxSamples: 5)
        try IdentityService.forget("Cecile", voicesURL: voices)
        XCTAssertTrue(try VoiceRegistry.load(from: voices).identities.isEmpty)
    }

    func testNameSpeakerWithoutTranscriptReturnsFalse() throws {
        let (dir, voices) = try fixture()
        defer { try? FileManager.default.removeItem(at: dir) }
        // Remove the transcript.json so relabel can't happen.
        try FileManager.default.removeItem(at: dir.appendingPathComponent("meeting-x.transcript.json"))
        let relabeled = try IdentityService.nameSpeaker(
            meeting: "meeting-x", label: "Speaker 1", name: "Cecile",
            notesFolder: dir, voicesURL: voices, maxSamples: 5)
        XCTAssertFalse(relabeled)                               // enrolled but not re-rendered
        XCTAssertEqual(try VoiceRegistry.load(from: voices).match([0, 1], threshold: 0.9)?.identity.name, "Cecile")
    }

    func testNameSpeakerReturnsTrueOnRelabel() throws {
        let (dir, voices) = try fixture()
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertTrue(try IdentityService.nameSpeaker(
            meeting: "meeting-x", label: "Speaker 1", name: "Cecile",
            notesFolder: dir, voicesURL: voices, maxSamples: 5))
    }

    func testNameSpeakerRejectsReservedAndUnsafeNames() throws {
        let (dir, voices) = try fixture()
        defer { try? FileManager.default.removeItem(at: dir) }
        for bad in ["", "  ", "Me", "Others", "Speaker 3", "A, B", "line\nbreak"] {
            XCTAssertThrowsError(try IdentityService.nameSpeaker(
                meeting: "meeting-x", label: "Speaker 1", name: bad,
                notesFolder: dir, voicesURL: voices, maxSamples: 5), "should reject '\(bad)'")
        }
    }
}
