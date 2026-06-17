import XCTest
@testable import Earwig

@MainActor
final class ContextDocsTests: XCTestCase {
    // MARK: - Helpers

    private func makeNotesFolder() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Writes a transcript-only meeting so reload() picks it up.
    private func writeMeeting(_ stem: String, text: String, in dir: URL) throws {
        let record = MeetingRecord(
            meeting: stem, date: 1_781_551_481, durationSeconds: 10,
            source: "test", mode: .full,
            turns: [TranscriptSegment(speaker: .me, start: 0, end: 5, text: text)])
        try record.write(to: dir.appendingPathComponent("\(stem).transcript.json"))
    }

    // MARK: - Tests

    func testEmptyServiceReturnsEmpty() async throws {
        let dir = try makeNotesFolder()
        defer { try? FileManager.default.removeItem(at: dir) }

        let svc = SearchService()
        await svc.reload(notesFolder: dir) // no meetings written — docs will be empty

        let result = svc.contextDocs(for: "budget", budgetChars: 100_000)
        XCTAssertTrue(result.isEmpty)
    }

    func testNoHitsReturnsEmpty() async throws {
        let dir = try makeNotesFolder()
        defer { try? FileManager.default.removeItem(at: dir) }

        try writeMeeting("meeting-2025-01-01-0900", text: "Completely unrelated content", in: dir)

        let svc = SearchService()
        await svc.reload(notesFolder: dir)

        let result = svc.contextDocs(for: "budget", budgetChars: 100_000)
        XCTAssertTrue(result.isEmpty)
    }

    func testTopMatchAlwaysIncludedEvenIfExceedsBudget() async throws {
        let dir = try makeNotesFolder()
        defer { try? FileManager.default.removeItem(at: dir) }

        try writeMeeting("meeting-2025-01-01-0900",
                         text: "We reviewed the budget carefully for the year.", in: dir)

        let svc = SearchService()
        await svc.reload(notesFolder: dir)

        // Budget of 1 is smaller than any doc, but the top match must still be included.
        let result = svc.contextDocs(for: "budget", budgetChars: 1)
        XCTAssertEqual(result.count, 1, "Top match must always be included regardless of budget")
    }

    func testDocsAreReturnedHighestScoringFirst() async throws {
        let dir = try makeNotesFolder()
        defer { try? FileManager.default.removeItem(at: dir) }

        // meetingA has "budget" mentioned many times -> higher score.
        try writeMeeting("meeting-2025-01-01-0900",
                         text: "budget budget budget forecast", in: dir)
        // meetingB has "budget" once -> lower score.
        try writeMeeting("meeting-2025-01-02-0900",
                         text: "general planning session with one budget mention", in: dir)

        let svc = SearchService()
        await svc.reload(notesFolder: dir)

        let result = svc.contextDocs(for: "budget", budgetChars: 100_000)
        XCTAssertEqual(result.first?.meetingId, "meeting-2025-01-01-0900",
                       "Higher-scoring meeting should appear first")
    }

    func testBudgetLimitsNumberOfDocs() async throws {
        let dir = try makeNotesFolder()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Write two meetings, each with ~50 chars of transcript.
        try writeMeeting("meeting-2025-01-01-0900",
                         text: "budget planning for the upcoming quarter review", in: dir)
        try writeMeeting("meeting-2025-01-02-0900",
                         text: "budget allocation discussed by the finance team", in: dir)

        let svc = SearchService()
        await svc.reload(notesFolder: dir)

        // Both transcripts are ~47-50 chars each. Budget of 55 fits the first but not both.
        let result = svc.contextDocs(for: "budget", budgetChars: 55)
        XCTAssertEqual(result.count, 1,
                       "Budget should stop accumulation after the first doc")
    }

    func testMultipleDocsIncludedWhenBudgetIsLarge() async throws {
        let dir = try makeNotesFolder()
        defer { try? FileManager.default.removeItem(at: dir) }

        try writeMeeting("meeting-2025-01-01-0900", text: "budget review first meeting", in: dir)
        try writeMeeting("meeting-2025-01-02-0900", text: "budget planning second meeting", in: dir)

        let svc = SearchService()
        await svc.reload(notesFolder: dir)

        // Large budget should include both matches.
        let result = svc.contextDocs(for: "budget", budgetChars: 100_000)
        XCTAssertEqual(result.count, 2, "All matching docs should be included when budget is large")
    }
}
