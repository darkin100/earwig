import XCTest
@testable import Earwig

final class TranscriptModelsTests: XCTestCase {
    func testSpeakerLabelDisplayNames() {
        XCTAssertEqual(SpeakerLabel.me.displayName, "Me")
        XCTAssertEqual(SpeakerLabel.remote(1).displayName, "Speaker 1")
        XCTAssertEqual(SpeakerLabel.remote(7).displayName, "Speaker 7")
        XCTAssertEqual(SpeakerLabel.others.displayName, "Others")
    }

    func testSpeakerLabelEquatable() {
        XCTAssertEqual(SpeakerLabel.remote(2), SpeakerLabel.remote(2))
        XCTAssertNotEqual(SpeakerLabel.remote(2), SpeakerLabel.remote(3))
    }

    func testNamedDisplayName() {
        XCTAssertEqual(SpeakerLabel.named("Cecile").displayName, "Cecile")
    }

    func testParseRoundTrip() {
        for label in [SpeakerLabel.me, .others, .remote(3), .named("Cecile")] {
            XCTAssertEqual(SpeakerLabel.parse(label.displayName), label)
        }
    }

    func testParseArbitraryNameBecomesNamed() {
        XCTAssertEqual(SpeakerLabel.parse("Dr. Strange"), .named("Dr. Strange"))
    }

    func testParseSpeakerNumberBecomesRemote() {
        XCTAssertEqual(SpeakerLabel.parse("Speaker 12"), .remote(12))
    }

    // MARK: - Time-range invariants (end is clamped to >= start)

    func testTimedSegmentClampsInvertedRange() {
        let seg = TimedSegment(text: "x", start: 5, end: 2)
        XCTAssertEqual(seg.start, 5)
        XCTAssertEqual(seg.end, 5)
    }

    func testSpeakerSegmentClampsInvertedRange() {
        let seg = SpeakerSegment(clusterId: 1, start: 4, end: 1)
        XCTAssertEqual(seg.end, 4)
    }

    func testTranscriptSegmentClampsInvertedRange() {
        let seg = TranscriptSegment(speaker: .me, start: 3, end: 1, text: "hi")
        XCTAssertEqual(seg.end, 3)
    }

    func testValidRangeIsUntouched() {
        let seg = TranscriptSegment(speaker: .me, start: 1, end: 4, text: "ok")
        XCTAssertEqual(seg.start, 1)
        XCTAssertEqual(seg.end, 4)
    }
}
