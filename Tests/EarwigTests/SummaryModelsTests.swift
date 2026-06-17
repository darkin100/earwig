import XCTest
@testable import Earwig

final class SummaryModelsTests: XCTestCase {
    func testSingleDefaultModel() {
        XCTAssertEqual(SummaryModels.catalog, [SummaryModels.defaultModel])
        XCTAssertEqual(SummaryModels.defaultModel.id, "qwen2.5:14b")
        XCTAssertEqual(SummaryModels.resolved(), SummaryModels.defaultModel)
        XCTAssertEqual(SummaryModels.resolved(override: ""), SummaryModels.defaultModel)
    }

    func testLegacyTagsUpgradeToDefault() {
        // Earlier weak defaults are transparently mapped to the current recommended model.
        for legacy in ["llama3.1:8b", "llama3.2:3b", "qwen2.5:3b"] {
            XCTAssertEqual(SummaryModels.resolved(override: legacy), SummaryModels.defaultModel)
            XCTAssertEqual(SummaryModels.model(for: legacy), SummaryModels.defaultModel)
        }
    }

    func testUnknownNonEmptyOverrideKeptAsCustom() {
        // A model the user pulled themselves is preserved, not discarded.
        let custom = SummaryModels.resolved(override: "mistral:7b")
        XCTAssertEqual(custom.id, "mistral:7b")
        XCTAssertEqual(custom.name, "mistral:7b")
    }
}

final class SummaryEngineKindTests: XCTestCase {
    func testDefaultsToOllamaForEmptyOrUnknown() {
        XCTAssertEqual(SummaryEngineKind.from(""), .ollama)
        XCTAssertEqual(SummaryEngineKind.from("garbage"), .ollama)
        XCTAssertEqual(SummaryEngineKind.from("apple"), .apple)
        XCTAssertEqual(SummaryEngineKind.from("ollama"), .ollama)
    }

    func testFromClaudeReturnsClaudeCase() {
        XCTAssertEqual(SummaryEngineKind.from("claude"), .claude)
    }

    func testAllCasesCountIsThree() {
        XCTAssertEqual(SummaryEngineKind.allCases.count, 3)
    }
}

final class OllamaClientTests: XCTestCase {
    func testChatRequestEncodesExpectedJSON() throws {
        let req = OllamaClient.chatRequest(model: "qwen2.5:3b", prompt: "hello", temperature: 0.2, maxTokens: 1400)
        let data = try JSONEncoder().encode(req)
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(obj["model"] as? String, "qwen2.5:3b")
        XCTAssertEqual(obj["stream"] as? Bool, false)
        XCTAssertEqual(obj["format"] as? String, "json")
        let options = try XCTUnwrap(obj["options"] as? [String: Any])
        XCTAssertEqual(options["temperature"] as? Double, 0.2)
        XCTAssertEqual(options["num_predict"] as? Int, 1400)
        XCTAssertNotNil(options["num_ctx"] as? Int)
        let messages = try XCTUnwrap(obj["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.first?["role"] as? String, "user")
        XCTAssertEqual(messages.first?["content"] as? String, "hello")
    }

    func testContextWindowSizing() {
        // Short prompt → the 8K floor (so a small chat isn't starved either).
        XCTAssertEqual(OllamaClient.contextWindow(forPrompt: "hi", maxTokens: 2048), 8192)
        // A long (~18-min) transcript must get a window bigger than Ollama's ~4K default.
        let long = String(repeating: "word ", count: 12_000) // ~60K chars ≈ 15K tokens
        XCTAssertGreaterThan(OllamaClient.contextWindow(forPrompt: long, maxTokens: 2048), 8192)
        // Enormous prompt is capped.
        let huge = String(repeating: "x", count: 1_000_000)
        XCTAssertEqual(OllamaClient.contextWindow(forPrompt: huge, maxTokens: 2048), 32768)
    }
}
