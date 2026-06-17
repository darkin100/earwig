import XCTest
@testable import Earwig

final class SummaryStoreTests: XCTestCase {
    func testRoundTrips() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("earwig-sum-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("meeting-x.summary.json")

        let summary = SummaryResult(
            tldr: "Synced on roadmap.",
            keyPoints: ["Ship beta"],
            decisions: ["Use MLX"],
            actionItems: [ActionItem(owner: "Nev", task: "Draft spec"),
                          ActionItem(owner: nil, task: "Follow up")])

        try SummaryStore.write(summary, meeting: "meeting-x", model: "Qwen3 8B",
                               templateID: "daily-standup", generatedAt: 1_000_000, to: url)
        let stored = try SummaryStore.read(from: url)

        XCTAssertEqual(stored.meeting, "meeting-x")
        XCTAssertEqual(stored.model, "Qwen3 8B")
        XCTAssertEqual(stored.templateID, "daily-standup")
        XCTAssertEqual(stored.generatedAt, 1_000_000, accuracy: 0.001)
        XCTAssertEqual(stored.summary, summary)
    }
}
