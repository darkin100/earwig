import XCTest
@testable import Earwig

final class SummaryServiceTests: XCTestCase {
    func testLLMTextJoinsSpeakerLabelledTurns() {
        let turns = [
            TranscriptSegment(speaker: .me, start: 0, end: 2, text: "  Hello there  "),
            TranscriptSegment(speaker: .remote(1), start: 2, end: 4, text: "Hi"),
            TranscriptSegment(speaker: .named("Hina"), start: 4, end: 6, text: "  "),  // empty → dropped
        ]
        XCTAssertEqual(SummaryService.llmText(turns: turns), "Me: Hello there\nSpeaker 1: Hi")
    }

    func testNoteBodyTextStripsFrontmatterAndHeaders() {
        let note = """
        ---
        date: 2026-06-15 21:12
        speakers: [Me, Speaker 1]
        ---

        # Meeting 2026-06-15 21:12

        ## Transcript

        **Me** · 00:02 – 00:09
        Hello, this is my voice.

        **Speaker 1** · 00:16 – 00:19
        How are you?
        """
        let body = SummaryService.noteBodyText(note)
        XCTAssertEqual(body, "Hello, this is my voice.\nHow are you?")
    }

    func testMarkdownRendersSections() {
        let result = SummaryResult(
            tldr: "Synced on roadmap.",
            keyPoints: ["Ship beta"],
            decisions: ["Use MLX"],
            actionItems: [ActionItem(owner: "Nev", task: "Draft spec"),
                          ActionItem(owner: nil, task: "Follow up")])
        let md = SummaryService.markdown(for: result)
        XCTAssertTrue(md.hasPrefix("## Summary\n\nSynced on roadmap."))
        XCTAssertTrue(md.contains("### Key points\n- Ship beta"))
        XCTAssertTrue(md.contains("### Decisions\n- Use MLX"))
        XCTAssertTrue(md.contains("- **Nev**: Draft spec"))
        XCTAssertTrue(md.contains("- Follow up"))
    }

    func testConfigSummaryDefaultsAndRoundTrip() throws {
        XCTAssertTrue(Config.defaultConfig.autoSummarize)
        XCTAssertEqual(Config.defaultConfig.summaryTemplateID, "daily-standup")
        XCTAssertEqual(Config.defaultConfig.summaryEngine, "ollama")
        XCTAssertEqual(Config.defaultConfig.summaryModelID, "qwen2.5:14b")
        XCTAssertEqual(Config.defaultConfig.summaryClaudeModel, "claude-sonnet-4-6")

        var cfg = Config.defaultConfig
        cfg.autoSummarize = false
        cfg.summaryTemplateID = "one-on-one"
        cfg.customSummaryInstructions = "Be terse."
        cfg.summaryEngine = "apple"
        cfg.summaryClaudeModel = "claude-opus-4-8"
        let decoded = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(cfg))
        XCTAssertFalse(decoded.autoSummarize)
        XCTAssertEqual(decoded.summaryTemplateID, "one-on-one")
        XCTAssertEqual(decoded.customSummaryInstructions, "Be terse.")
        XCTAssertEqual(decoded.summaryEngine, "apple")
        XCTAssertEqual(decoded.summaryClaudeModel, "claude-opus-4-8")
    }

    func testOldConfigDefaultsSummaryFields() throws {
        let old = """
        { "notesFolder": "/n", "audioFolder": "/n/a", "keepAudio": true, "localeIdentifier": "en_GB" }
        """.data(using: .utf8)!
        let cfg = try JSONDecoder().decode(Config.self, from: old)
        XCTAssertTrue(cfg.autoSummarize)
        XCTAssertEqual(cfg.summaryTemplateID, "daily-standup")
    }
}
