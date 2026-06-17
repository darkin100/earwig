import XCTest
@testable import Earwig

final class TranscriberJoinTests: XCTestCase {
    func testJoinSegments() {
        let segs = [
            TimedSegment(text: "Hello", start: 0, end: 1),
            TimedSegment(text: "world", start: 1, end: 2),
        ]
        XCTAssertEqual(Transcriber.join(segs), "Hello world")
    }

    func testJoinTrimsAndSkipsEmpty() {
        let segs = [
            TimedSegment(text: " Hello ", start: 0, end: 1),
            TimedSegment(text: "", start: 1, end: 2),
            TimedSegment(text: "world", start: 2, end: 3),
        ]
        XCTAssertEqual(Transcriber.join(segs), "Hello world")
    }
}
