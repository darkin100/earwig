import XCTest
@testable import Earwig

final class ClaudeClientTests: XCTestCase {
    // MARK: - RequestBody JSON encoding

    func testRequestBodyEncodesExpectedKeys() throws {
        let body = ClaudeClient.requestBody(
            model: "claude-sonnet-4-6",
            system: "You are a meeting summariser.",
            prompt: "Hello, Claude.",
            maxTokens: 1024
        )
        let data = try JSONEncoder().encode(body)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(obj["model"] as? String, "claude-sonnet-4-6")
        XCTAssertEqual(obj["max_tokens"] as? Int, 1024)
        XCTAssertEqual(obj["system"] as? String, "You are a meeting summariser.")

        let messages = try XCTUnwrap(obj["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?["role"] as? String, "user")
        XCTAssertEqual(messages.first?["content"] as? String, "Hello, Claude.")
    }

    func testRequestBodyDefaultMaxTokens() throws {
        let body = ClaudeClient.requestBody(
            model: "claude-sonnet-4-6",
            system: "sys",
            prompt: "hi",
            maxTokens: 2048
        )
        let data = try JSONEncoder().encode(body)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(obj["max_tokens"] as? Int, 2048)
    }

    // MARK: - Error descriptions (British English, no em dashes)

    func testNoKeyErrorDescription() {
        let err = ClaudeClient.ClaudeError.noKey
        XCTAssertNotNil(err.errorDescription)
        XCTAssertFalse(err.errorDescription?.contains("\u{2014}") ?? false, "Should not contain em dash")
        XCTAssertFalse(err.errorDescription?.contains("\u{2013}") ?? false, "Should not contain en dash")
    }

    func testHTTPErrorDescription() {
        let err = ClaudeClient.ClaudeError.http(429, "rate limited")
        XCTAssertNotNil(err.errorDescription)
        XCTAssertTrue(err.errorDescription?.lowercased().contains("rate") ?? false)
    }

    func testHTTPNon429ErrorDescription() {
        let err = ClaudeClient.ClaudeError.http(500, "server error")
        XCTAssertNotNil(err.errorDescription)
    }

    func testDecodeErrorDescription() {
        let err = ClaudeClient.ClaudeError.decode("unexpected field")
        XCTAssertNotNil(err.errorDescription)
    }

    // MARK: - Default property values

    func testDefaultMaxTokens() {
        let client = ClaudeClient(model: "claude-sonnet-4-6")
        XCTAssertEqual(client.maxTokens, 2048)
    }
}
