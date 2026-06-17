import XCTest
@testable import Earwig

final class SummaryResultTests: XCTestCase {
    func testParsesBareJSON() {
        let raw = """
        {"tldr":"Synced on the roadmap.","keyPoints":["Ship beta","Hire QA"],
         "decisions":["Use MLX"],"actionItems":[{"owner":"Nev","task":"Draft spec"}]}
        """
        let r = SummaryResult.parse(raw)
        XCTAssertEqual(r?.tldr, "Synced on the roadmap.")
        XCTAssertEqual(r?.keyPoints, ["Ship beta", "Hire QA"])
        XCTAssertEqual(r?.decisions, ["Use MLX"])
        XCTAssertEqual(r?.actionItems, [ActionItem(owner: "Nev", task: "Draft spec")])
    }

    func testParsesFencedAndProseWrapped() {
        let raw = """
        Sure! Here is the summary:
        ```json
        {"tldr":"Quick standup.","keyPoints":[],"decisions":[],"actionItems":[]}
        ```
        Hope that helps.
        """
        XCTAssertEqual(SummaryResult.parse(raw)?.tldr, "Quick standup.")
    }

    func testToleratesBracesInsideStrings() {
        let raw = #"{"tldr":"Discussed the {edge} case","keyPoints":[],"decisions":[],"actionItems":[]}"#
        XCTAssertEqual(SummaryResult.parse(raw)?.tldr, "Discussed the {edge} case")
    }

    func testNullOwnerBecomesNil() {
        let raw = #"{"tldr":"x","keyPoints":[],"decisions":[],"actionItems":[{"owner":null,"task":"Follow up"}]}"#
        XCTAssertEqual(SummaryResult.parse(raw)?.actionItems, [ActionItem(owner: nil, task: "Follow up")])
    }

    func testPartialObjectDefaultsEmptyFields() {
        let r = SummaryResult.parse(#"{"tldr":"Only a tldr here"}"#)
        XCTAssertEqual(r?.tldr, "Only a tldr here")
        XCTAssertEqual(r?.keyPoints, [])
        XCTAssertEqual(r?.actionItems, [])
    }

    func testMalformedOrEmptyReturnsNil() {
        XCTAssertNil(SummaryResult.parse("no json here"))
        XCTAssertNil(SummaryResult.parse(#"{"tldr":"","keyPoints":[],"decisions":[],"actionItems":[]}"#))
        XCTAssertNil(SummaryResult.parse(""))
    }
}
