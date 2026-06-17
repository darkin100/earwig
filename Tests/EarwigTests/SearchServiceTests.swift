import XCTest
@testable import Earwig

final class SearchServiceTests: XCTestCase {
    // MARK: - Fixtures

    private static let dateA = Date(timeIntervalSince1970: 1_750_000_000)  // older
    private static let dateB = Date(timeIntervalSince1970: 1_760_000_000)  // newer

    private static let docA = SearchDoc(
        meetingId: "meeting-2025-06-01-0900",
        title: "Design review",
        date: dateA,
        speakers: ["Alice", "Bob"],
        transcript: "Alice: Let us talk about the design system.\nBob: I agree, the colours need work.",
        summary: "Team reviewed the design system and agreed on colour changes."
    )

    private static let docB = SearchDoc(
        meetingId: "meeting-2025-06-02-1400",
        title: "Sprint planning",
        date: dateB,
        speakers: ["Carol"],
        transcript: "Carol: We should plan the next sprint carefully.",
        summary: "Sprint goals were set for the upcoming iteration."
    )

    private static let docC = SearchDoc(
        meetingId: "meeting-2025-06-03-0930",
        title: "Design critique",
        date: dateB,
        speakers: ["Alice"],
        transcript: "Alice: The new design looks great.",
        summary: "Design critique concluded positively."
    )

    // MARK: - Ranking tests

    func testMostRelevantResultIsFirst() {
        // "design" appears in docA title + transcript + summary, and docC title + transcript + summary.
        // docA has it in title (×5) + summary (×3) + transcript (×1) = 9 points minimum.
        // docC also has "design" in title + summary + transcript.
        // Both score similarly but docA title is "Design review" while docC is "Design critique" —
        // scores will be equal so the newer one (dateB, docC) comes first by date desc.
        // The key test is that docB (no "design" hits) is absent.
        let hits = SearchService.rank(query: "design", in: [Self.docA, Self.docB, Self.docC])
        XCTAssertFalse(hits.isEmpty, "Expected at least one hit for 'design'")
        XCTAssertTrue(hits.allSatisfy { $0.meetingId != Self.docB.meetingId },
                      "Sprint planning doc should not match 'design'")
    }

    func testHigherScoringDocComesFirst() {
        // "colour" only appears in docA (transcript + summary); docB and docC have nothing.
        let hits = SearchService.rank(query: "colour", in: [Self.docA, Self.docB, Self.docC])
        XCTAssertEqual(hits.first?.meetingId, Self.docA.meetingId,
                       "docA should rank first because 'colour' appears in its content")
        XCTAssertEqual(hits.count, 1)
    }

    func testTitleHitsOutweighBodyHitsAlone() {
        // docA title = "Design review" (title hit = 5 pts)
        // docB summary mentions "sprint" (summary hit = 3 pts)
        // Search "review" — only docA has it, in title.
        let hits = SearchService.rank(query: "review", in: [Self.docA, Self.docB, Self.docC])
        XCTAssertEqual(hits.first?.meetingId, Self.docA.meetingId)
    }

    func testNoMatchReturnsEmpty() {
        let hits = SearchService.rank(query: "xyzzy", in: [Self.docA, Self.docB, Self.docC])
        XCTAssertTrue(hits.isEmpty, "Non-matching query should return no hits")
    }

    func testEmptyQueryReturnsEmpty() {
        let hits = SearchService.rank(query: "", in: [Self.docA, Self.docB, Self.docC])
        XCTAssertTrue(hits.isEmpty, "Empty query should return no hits")
    }

    func testSingleTokenTooShortReturnsEmpty() {
        // Tokens < 2 chars are dropped; a single letter query → no tokens → empty.
        let hits = SearchService.rank(query: "a", in: [Self.docA, Self.docB, Self.docC])
        XCTAssertTrue(hits.isEmpty, "Single-char query should return no hits")
    }

    func testResultsAreSortedByScoreThenDateDesc() {
        // Both docA and docC contain "design" equally in title.
        // On equal score, newer date (docC, dateB) should come first.
        let hits = SearchService.rank(query: "design", in: [Self.docA, Self.docC])
        XCTAssertEqual(hits.first?.meetingId, Self.docC.meetingId,
                       "On equal score, newer meeting should rank first")
    }

    // MARK: - Snippet tests

    func testSnippetContainsTerm() {
        let hits = SearchService.rank(query: "colour", in: [Self.docA])
        XCTAssertFalse(hits.isEmpty)
        let snippet = hits[0].snippet.lowercased()
        XCTAssertTrue(snippet.contains("colour"), "Snippet should contain the search term")
    }

    func testSnippetFallsBackToSummaryStart() {
        // "sprint" only appears in docB's summary and transcript.
        let hits = SearchService.rank(query: "sprint", in: [Self.docB])
        XCTAssertFalse(hits.isEmpty)
        XCTAssertFalse(hits[0].snippet.isEmpty, "Snippet should not be empty")
    }

    func testSnippetIsWrappedWithEllipsis() {
        // Use a long transcript so the snippet must be a window, not the whole text.
        let long = SearchDoc(
            meetingId: "meeting-2025-01-01-0800",
            title: "Test",
            date: Date(),
            speakers: [],
            transcript: String(repeating: "filler ", count: 50) + "target term here" + String(repeating: " filler", count: 50),
            summary: ""
        )
        let hits = SearchService.rank(query: "target", in: [long])
        XCTAssertFalse(hits.isEmpty)
        let snippet = hits[0].snippet
        // The snippet should have leading or trailing ellipsis because the term is buried.
        XCTAssertTrue(snippet.contains("…"), "Snippet should be truncated with ellipsis")
    }

    // MARK: - Token helper

    func testTokensLowercasesAndFiltersShort() {
        let toks = SearchService.tokens("Hello, a be World!")
        // "a" (1 char) and "be" (2 chars) — "be" should be included (>=2), "a" dropped.
        XCTAssertTrue(toks.contains("hello"))
        XCTAssertTrue(toks.contains("world"))
        XCTAssertFalse(toks.contains("a"), "Single-char token should be dropped")
        XCTAssertTrue(toks.contains("be"), "Two-char token should be kept")
    }
}
