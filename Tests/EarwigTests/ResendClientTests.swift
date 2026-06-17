import XCTest
@testable import Earwig

final class ResendClientTests: XCTestCase {
    private func feedback(
        mood: Feedback.Mood = .happy,
        category: Feedback.Category = .general,
        message: String = "Great app",
        email: String = ""
    ) -> Feedback {
        Feedback(mood: mood, category: category, message: message, contactEmail: email)
    }

    func testRequestBodyAddressesTheRecipient() {
        let body = ResendClient.requestBody(for: feedback(), version: "1.0 (5)")
        XCTAssertEqual(body.to, [ResendClient.recipient])
        XCTAssertEqual(body.from, ResendClient.fromAddress)
    }

    func testSubjectIncludesCategoryMoodAndEmoji() {
        let body = ResendClient.requestBody(
            for: feedback(mood: .unhappy, category: .bug), version: "1.0 (5)")
        XCTAssertTrue(body.subject.contains("Earwig feedback: Report a bug (Unhappy)"))
        XCTAssertTrue(body.subject.hasPrefix("☹️🐞"))
    }

    func testBodyTextContainsMessageAndVersion() {
        let body = ResendClient.requestBody(
            for: feedback(message: "Crashes on launch"), version: "0.2.0 (87)")
        XCTAssertTrue(body.text.contains("Crashes on launch"))
        XCTAssertTrue(body.text.contains("0.2.0 (87)"))
    }

    func testReplyToOmittedWhenNoEmail() {
        let body = ResendClient.requestBody(for: feedback(email: ""), version: "1.0 (5)")
        XCTAssertNil(body.reply_to)
    }

    func testReplyToSetWhenEmailProvided() {
        let body = ResendClient.requestBody(for: feedback(email: " me@example.com "), version: "1.0 (5)")
        XCTAssertEqual(body.reply_to, "me@example.com")
        XCTAssertTrue(body.text.contains("me@example.com"))
    }

    func testErrorMessageExtractsResendMessage() {
        let json = Data(#"{"message":"Invalid API key","name":"validation_error"}"#.utf8)
        XCTAssertEqual(ResendClient.errorMessage(from: json), "Invalid API key")
    }
}
