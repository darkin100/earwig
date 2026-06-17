import XCTest
@testable import Earwig

@MainActor
final class MeetingsStoreDeleteTests: XCTestCase {
    private func makeDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("earwig-delete-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Writes a note plus every sidecar (transcript, summary, speakers, notes, audio) for a stem.
    private func writeMeeting(_ stem: String, notes: URL, audio: URL) throws {
        let md = """
        ---
        source: Test Meeting
        date: 2026-06-15 10:00
        duration_minutes: 5
        speakers: [Me]
        ---
        ## Transcript
        Hello world, this is a test meeting with plenty of spoken words to parse.
        """
        try md.write(to: notes.appendingPathComponent("\(stem).md"), atomically: true, encoding: .utf8)
        for ext in ["transcript.json", "summary.json", "speakers.json", "notes.md"] {
            try "{}".write(to: notes.appendingPathComponent("\(stem).\(ext)"), atomically: true, encoding: .utf8)
        }
        try Data().write(to: audio.appendingPathComponent("\(stem).m4a"))
    }

    func testDeleteRemovesOnlyTargetMeetingFiles() throws {
        let notes = try makeDir()
        let audio = try makeDir()
        defer {
            try? FileManager.default.removeItem(at: notes)
            try? FileManager.default.removeItem(at: audio)
        }

        try writeMeeting("meeting-2026-06-15-1000", notes: notes, audio: audio)
        try writeMeeting("meeting-2026-06-15-1100", notes: notes, audio: audio)

        let store = MeetingsStore(notesFolder: notes, audioFolder: audio)
        XCTAssertEqual(store.meetings.count, 2)

        let target = try XCTUnwrap(store.meetings.first { $0.id == "meeting-2026-06-15-1000" })
        XCTAssertTrue(store.delete(target))

        // Every file belonging to the target is gone.
        for url in Meeting.associatedFileURLs(stem: target.id, notesFolder: notes, audioFolder: audio) {
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path),
                           "\(url.lastPathComponent) should be deleted")
        }
        // The unrelated meeting is untouched.
        for url in Meeting.associatedFileURLs(
            stem: "meeting-2026-06-15-1100", notesFolder: notes, audioFolder: audio) {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path),
                          "\(url.lastPathComponent) should remain")
        }
        // The store reloaded itself: target gone, unrelated still listed.
        XCTAssertFalse(store.meetings.contains { $0.id == target.id })
        XCTAssertTrue(store.meetings.contains { $0.id == "meeting-2026-06-15-1100" })
    }

    func testDeleteSucceedsWhenSomeSidecarsAbsent() throws {
        let notes = try makeDir()
        let audio = try makeDir()
        defer {
            try? FileManager.default.removeItem(at: notes)
            try? FileManager.default.removeItem(at: audio)
        }

        try writeMeeting("meeting-2026-06-15-0900", notes: notes, audio: audio)
        // Remove the audio so a sidecar is missing; delete should still report success.
        try FileManager.default.removeItem(at: audio.appendingPathComponent("meeting-2026-06-15-0900.m4a"))

        let store = MeetingsStore(notesFolder: notes, audioFolder: audio)
        let target = try XCTUnwrap(store.meetings.first)
        XCTAssertTrue(store.delete(target))
        XCTAssertTrue(store.meetings.isEmpty)
    }
}
