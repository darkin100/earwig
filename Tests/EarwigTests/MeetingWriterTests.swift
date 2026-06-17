import XCTest
@testable import Earwig

final class MeetingWriterTests: XCTestCase {
    private func makeConfig(in dir: URL, keepEmbeddings: Bool = true) -> Config {
        Config(
            notesFolder: dir.path, audioFolder: dir.appendingPathComponent("audio").path,
            keepAudio: true, localeIdentifier: "en_GB",
            keepSpeakerEmbeddings: keepEmbeddings)
    }

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("earwig-writer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testDiarizedOutputWritesNoteAndBothSidecars() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cfg = makeConfig(in: dir)

        let output = DiarizedTranscriber.Output.diarized(
            turns: [TranscriptSegment(speaker: .remote(1), start: 0, end: 2, text: "hi")],
            speakers: [.remote(1)],
            profiles: [SpeakerProfile(label: .remote(1), embedding: [0.1, 0.2], speechSeconds: 2)])

        let result = try MeetingWriter.write(
            output, stamp: "2026-06-14-1200", meetingDate: Date(timeIntervalSince1970: 1_000_000),
            duration: 2, apps: ["Microsoft Teams"], config: cfg)

        XCTAssertEqual(result.mode, .full)
        XCTAssertTrue(result.sidecarsComplete)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("meeting-2026-06-14-1200.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("meeting-2026-06-14-1200.speakers.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("meeting-2026-06-14-1200.transcript.json").path))
    }

    func testPlainOutputWritesNoteOnly() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cfg = makeConfig(in: dir)

        let result = try MeetingWriter.write(
            .plain(text: "a single block"), stamp: "s", meetingDate: Date(),
            duration: 0, apps: [], config: cfg)

        XCTAssertEqual(result.mode, .none)
        XCTAssertTrue(result.sidecarsComplete)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("meeting-s.md").path))
        // .plain carries no speakers and no structured turns — no sidecars.
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("meeting-s.speakers.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("meeting-s.transcript.json").path))
    }

    func testKeepEmbeddingsDisabledSkipsSpeakersSidecar() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cfg = makeConfig(in: dir, keepEmbeddings: false)

        let output = DiarizedTranscriber.Output.diarized(
            turns: [TranscriptSegment(speaker: .remote(1), start: 0, end: 1, text: "x")],
            speakers: [.remote(1)],
            profiles: [SpeakerProfile(label: .remote(1), embedding: [0.5], speechSeconds: 1)])

        let result = try MeetingWriter.write(
            output, stamp: "s", meetingDate: Date(), duration: 1, apps: [], config: cfg)

        XCTAssertTrue(result.sidecarsComplete)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("meeting-s.speakers.json").path))
        // transcript.json still written (independent of keepSpeakerEmbeddings).
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("meeting-s.transcript.json").path))
    }
}
