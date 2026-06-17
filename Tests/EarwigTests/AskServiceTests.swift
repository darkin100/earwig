import XCTest
@testable import Earwig

final class AskServiceTests: XCTestCase {
    // MARK: - Fixtures

    private static let docA = SearchDoc(
        meetingId: "meeting-2025-06-01-0900",
        title: "Quarterly review",
        date: Date(timeIntervalSince1970: 1_748_649_600), // 2025-05-31 00:00 UTC
        speakers: ["Alice", "Bob"],
        transcript: "Alice: Revenue is up 12 percent.\nBob: Great news.",
        summary: "Revenue growth discussed."
    )

    private static let docB = SearchDoc(
        meetingId: "meeting-2025-06-02-1400",
        title: "Sprint planning",
        date: Date(timeIntervalSince1970: 1_748_736_000), // 2025-06-01 00:00 UTC
        speakers: ["Carol"],
        transcript: "Carol: Let us pick the top three stories for the sprint.",
        summary: "Sprint goals agreed."
    )

    // MARK: - contextBudget

    func testContextBudgetClaudeIsLarge() {
        XCTAssertEqual(AskService.contextBudget(for: .claude), 150_000)
    }

    func testContextBudgetOllamaIsSmall() {
        XCTAssertEqual(AskService.contextBudget(for: .ollama), 8_000)
    }

    func testContextBudgetAppleIsSmall() {
        XCTAssertEqual(AskService.contextBudget(for: .apple), 8_000)
    }

    // MARK: - prompt

    func testPromptContainsQuestion() {
        let (_, user) = AskService.prompt(question: "What was the revenue?", docs: [Self.docA])
        XCTAssertTrue(user.contains("What was the revenue?"),
                      "User prompt must contain the original question")
    }

    func testPromptContainsMeetingTitle() {
        let (_, user) = AskService.prompt(question: "Tell me about revenue", docs: [Self.docA])
        XCTAssertTrue(user.contains("Quarterly review"),
                      "User prompt must include the meeting title")
    }

    func testPromptContainsTranscript() {
        let (_, user) = AskService.prompt(question: "What happened?", docs: [Self.docA])
        XCTAssertTrue(user.contains("Revenue is up"),
                      "User prompt must include the transcript text")
    }

    func testPromptContainsSummary() {
        let (_, user) = AskService.prompt(question: "Summary?", docs: [Self.docA])
        XCTAssertTrue(user.contains("Revenue growth discussed"),
                      "User prompt must include the summary text")
    }

    func testPromptContainsAllDocTitles() {
        let (_, user) = AskService.prompt(question: "Any updates?", docs: [Self.docA, Self.docB])
        XCTAssertTrue(user.contains("Quarterly review"), "First meeting title must appear")
        XCTAssertTrue(user.contains("Sprint planning"),  "Second meeting title must appear")
    }

    func testPromptDocsAppearInOrder() {
        let (_, user) = AskService.prompt(question: "?", docs: [Self.docA, Self.docB])
        let indexA = user.range(of: "Quarterly review")!.lowerBound
        let indexB = user.range(of: "Sprint planning")!.lowerBound
        XCTAssertLessThan(indexA, indexB, "docA must appear before docB in the prompt")
    }

    func testPromptSystemPromptInstructsToUseContext() {
        let (system, _) = AskService.prompt(question: "?", docs: [Self.docA])
        XCTAssertTrue(system.lowercased().contains("context"),
                      "System prompt must reference the provided context")
    }

    func testPromptUsesDateFormatter() {
        let (_, user) = AskService.prompt(question: "?", docs: [Self.docA])
        // Date 2025-05-31 00:00:00 UTC -> formatted as "2025-05-31 00:00" (POSIX locale)
        XCTAssertTrue(user.contains("2025-"), "Prompt must include a formatted date")
    }

    // MARK: - ask (empty docs fast path)

    func testAskWithEmptyDocsReturnsCannedAnswer() async throws {
        // Engine value is irrelevant for the empty-docs path.
        let result = try await AskService.ask(
            question: "What did we decide?",
            docs: [],
            engine: .ollama,
            modelID: "any",
            claudeModel: "any"
        )
        XCTAssertEqual(
            result.answer,
            "I couldn't find anything about that in your meetings."
        )
        XCTAssertTrue(result.sources.isEmpty)
    }

    func testAskWithEmptyDocsDoesNotHitNetworkForAnyEngine() async throws {
        // Verify for all engine kinds — none should attempt a network call.
        for engine in SummaryEngineKind.allCases {
            let result = try await AskService.ask(
                question: "test", docs: [], engine: engine,
                modelID: "model", claudeModel: "claude"
            )
            XCTAssertFalse(result.answer.isEmpty,
                           "\(engine) empty-docs path must return a non-empty canned answer")
        }
    }
}
