import XCTest
@testable import Earwig

final class MeetingRecordTests: XCTestCase {
    func testRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("earwig-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("m.transcript.json")

        let turns = [
            TranscriptSegment(speaker: .me, start: 0, end: 2, text: "Hi"),
            TranscriptSegment(speaker: .named("Cecile"), start: 2, end: 5, text: "Hello"),
            TranscriptSegment(speaker: .remote(2), start: 5, end: 7, text: "Yo"),
        ]
        let rec = MeetingRecord(
            meeting: "m", date: 1_000_000, durationSeconds: 7,
            source: "Microsoft Teams", mode: .full, turns: turns)
        try rec.write(to: url)

        let loaded = try MeetingRecord.read(from: url)
        XCTAssertEqual(loaded.meeting, "m")
        XCTAssertEqual(loaded.source, "Microsoft Teams")
        XCTAssertEqual(loaded.mode, .full)
        XCTAssertEqual(loaded.turns.map(\.speaker), [.me, .named("Cecile"), .remote(2)])
        XCTAssertEqual(loaded.turns[1].text, "Hello")
    }
}
