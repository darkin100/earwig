import XCTest
@testable import Earwig

final class SummaryTemplateTests: XCTestCase {
    func testDefaultIsDailyStandup() {
        XCTAssertEqual(SummaryTemplate.defaultID, "daily-standup")
        XCTAssertEqual(SummaryTemplate.byID("daily-standup"), SummaryTemplate.dailyStandup)
    }

    func testByIDFallsBackToDefault() {
        XCTAssertEqual(SummaryTemplate.byID("does-not-exist"), SummaryTemplate.dailyStandup)
    }

    func testPromptIncludesTranscriptInstructionsAndSchema() {
        let p = SummaryTemplate.dailyStandup.prompt(for: "Me: hello\n\nSpeaker 1: hi")
        XCTAssertTrue(p.contains("Me: hello"))
        XCTAssertTrue(p.contains("Teams"))            // built-in guidance present
        XCTAssertTrue(p.contains("\"actionItems\""))   // JSON schema present
        XCTAssertTrue(p.contains("\"tldr\""))
    }

    func testCustomInstructionsOverrideBuiltIn() {
        let p = SummaryTemplate.dailyStandup.prompt(
            for: "transcript", custom: "Summarize in pirate speak.")
        XCTAssertTrue(p.contains("pirate speak"))
        XCTAssertFalse(p.contains("Teams"))            // built-in guidance replaced
        XCTAssertTrue(p.contains("\"actionItems\""))   // schema still appended
    }
}
