import XCTest
@testable import Earwig

final class TranscriptNoteTests: XCTestCase {
    private func fixedDate() -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 6; c.day = 13; c.hour = 16; c.minute = 17
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    func testStructuredRenderHasFrontmatterAndTurns() {
        let turns = [
            TranscriptSegment(speaker: .remote(1), start: 10, end: 222,
                              text: "Uh, but I don't want to talk to solution."),
            TranscriptSegment(speaker: .me, start: 223, end: 226,
                              text: "Yeah, great initial insights."),
        ]
        let md = TranscriptNote.markdown(
            turns: turns,
            speakers: [.me, .remote(1)],
            mode: .full,
            meetingDate: fixedDate(),
            duration: 226,
            apps: ["Microsoft Teams"])

        XCTAssertTrue(md.contains("diarization: full"))
        XCTAssertTrue(md.contains("speakers: [Me, Speaker 1]"))
        XCTAssertTrue(md.contains("source: Microsoft Teams"))
        XCTAssertTrue(md.contains("status: raw-transcript"))
        XCTAssertTrue(md.contains("**Speaker 1** · 00:10 – 03:42"))
        XCTAssertTrue(md.contains("Uh, but I don't want to talk to solution."))
        XCTAssertTrue(md.contains("**Me** · 03:43 – 03:46"))
    }

    func testStructuredRenderHandlesEmptyTurns() {
        let md = TranscriptNote.markdown(
            turns: [], speakers: [], mode: .full,
            meetingDate: fixedDate(), duration: 0, apps: [])
        XCTAssertTrue(md.contains("diarization: full"))
        XCTAssertTrue(md.contains("speakers: []"))
        XCTAssertTrue(md.contains("## Transcript"))
    }

    func testStructuredRenderNormalizesTurnWhitespace() {
        let turns = [
            TranscriptSegment(speaker: .remote(1), start: 0, end: 5,
                              text: " Hello,  who?   A  piece "),
        ]
        let md = TranscriptNote.markdown(
            turns: turns, speakers: [.remote(1)], mode: .full,
            meetingDate: fixedDate(), duration: 5, apps: [])
        XCTAssertTrue(md.contains("Hello, who? A piece"))
        XCTAssertFalse(md.contains("  ")) // no double spaces anywhere in the note
    }

    func testPlainRenderUnchangedForFallback() {
        let md = TranscriptNote.markdown(
            transcript: "just one block",
            meetingDate: fixedDate(),
            duration: 60,
            apps: [])
        XCTAssertTrue(md.contains("## Transcript"))
        XCTAssertTrue(md.contains("just one block"))
        XCTAssertTrue(md.contains("source: manual recording"))
    }
}
