import XCTest
@testable import Earwig

@MainActor
final class SearchServiceReloadTests: XCTestCase {
    private func makeNotesFolder() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func writeMeeting(_ stem: String, text: String, in dir: URL) throws {
        let record = MeetingRecord(
            meeting: stem, date: 1_781_551_481, durationSeconds: 38,
            source: "manual recording", mode: .full,
            turns: [TranscriptSegment(speaker: .me, start: 0, end: 5, text: text)])
        try record.write(to: dir.appendingPathComponent("\(stem).transcript.json"))
    }

    func testReloadIndexesTranscriptStems() async throws {
        let dir = try makeNotesFolder()
        defer { try? FileManager.default.removeItem(at: dir) }

        try writeMeeting("meeting-2026-06-15-2024", text: "We discussed the budget forecast", in: dir)
        try writeMeeting("meeting-2026-06-15-2025", text: "Planning the product roadmap", in: dir)

        let svc = SearchService()
        await svc.reload(notesFolder: dir)

        XCTAssertEqual(svc.docs.count, 2)
    }

    func testReloadedDocsAreSearchable() async throws {
        let dir = try makeNotesFolder()
        defer { try? FileManager.default.removeItem(at: dir) }

        try writeMeeting("meeting-2026-06-15-2024", text: "We discussed the budget forecast", in: dir)

        let svc = SearchService()
        await svc.reload(notesFolder: dir)

        let hits = SearchService.rank(query: "budget", in: svc.docs)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.meetingId, "meeting-2026-06-15-2024")
    }

    func testReloadOnMissingFolderYieldsNoDocs() async {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let svc = SearchService()
        await svc.reload(notesFolder: missing)
        XCTAssertTrue(svc.docs.isEmpty)
    }
}
