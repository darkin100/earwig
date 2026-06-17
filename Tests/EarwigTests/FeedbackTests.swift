import XCTest
@testable import Earwig

final class FeedbackTests: XCTestCase {
    private func make(_ message: String, email: String = "") -> Feedback {
        Feedback(mood: .happy, category: .general, message: message, contactEmail: email)
    }

    func testEmptyMessageIsInvalid() {
        XCTAssertFalse(make("").isValid)
    }

    func testWhitespaceOnlyMessageIsInvalid() {
        XCTAssertFalse(make("   \n  ").isValid)
    }

    func testMessageWithContentIsValid() {
        XCTAssertTrue(make("Love the app").isValid)
    }

    func testTrimmedMessageStripsSurroundingWhitespace() {
        XCTAssertEqual(make("  hello  ").trimmedMessage, "hello")
    }

    func testTrimmedEmailStripsSurroundingWhitespace() {
        XCTAssertEqual(make("x", email: "  me@x.com ").trimmedEmail, "me@x.com")
    }

    func testCategoryLabels() {
        XCTAssertEqual(Feedback.Category.bug.label, "Report a bug")
        XCTAssertEqual(Feedback.Category.feature.label, "Suggest a feature")
        XCTAssertEqual(Feedback.Category.general.label, "General")
    }

    func testMoodSymbols() {
        XCTAssertEqual(Feedback.Mood.happy.symbol, "face.smiling")
        XCTAssertEqual(Feedback.Mood.unhappy.symbol, "face.dashed")
    }
}
