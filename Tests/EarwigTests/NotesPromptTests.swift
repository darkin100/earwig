import XCTest
@testable import Earwig

final class NotesPromptTests: XCTestCase {
    func testPromptWithoutNotesIsUnchanged() {
        let withoutNotes = SummaryTemplate.general.prompt(for: "Speaker 1: hello")
        let withEmptyNotes = SummaryTemplate.general.prompt(for: "Speaker 1: hello", notes: "")
        XCTAssertEqual(withoutNotes, withEmptyNotes)
    }

    func testPromptWithNotesInjectsLabelAndText() {
        let p = SummaryTemplate.general.prompt(
            for: "Speaker 1: hello",
            notes: "Key takeaway: ship by Friday.")
        XCTAssertTrue(p.contains("attendee also wrote"))
        XCTAssertTrue(p.contains("Key takeaway: ship by Friday."))
    }

    func testNotesAppearBeforeTranscript() {
        let p = SummaryTemplate.general.prompt(
            for: "Me: hi",
            notes: "My note.")
        let notesRange = p.range(of: "My note.")!
        let transcriptRange = p.range(of: "Transcript:")!
        XCTAssertLessThan(notesRange.lowerBound, transcriptRange.lowerBound)
    }

    func testPromptWithWhitespaceOnlyNotesIsUnchanged() {
        let withoutNotes = SummaryTemplate.dailyStandup.prompt(for: "Me: morning")
        let withSpaceNotes = SummaryTemplate.dailyStandup.prompt(
            for: "Me: morning", notes: "   \n  ")
        XCTAssertEqual(withoutNotes, withSpaceNotes)
    }

    func testCustomInstructionsWithNotesIncludesBoth() {
        let p = SummaryTemplate.general.prompt(
            for: "Me: hi",
            custom: "Be brief.",
            notes: "Important context.")
        XCTAssertTrue(p.contains("Be brief."))
        XCTAssertTrue(p.contains("Important context."))
        XCTAssertTrue(p.contains("attendee also wrote"))
    }
}
