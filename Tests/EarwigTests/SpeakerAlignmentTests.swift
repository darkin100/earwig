import XCTest
@testable import Earwig

final class SpeakerAlignmentTests: XCTestCase {
    func testOverlap() {
        XCTAssertEqual(SpeakerAlignment.overlap(0, 2, 1, 3), 1, accuracy: 0.0001)
        XCTAssertEqual(SpeakerAlignment.overlap(0, 2, 2, 4), 0, accuracy: 0.0001)
        XCTAssertEqual(SpeakerAlignment.overlap(0, 5, 1, 3), 2, accuracy: 0.0001)
    }

    func testEachWordToBestCluster() {
        let words = [
            TimedSegment(text: "hello", start: 0, end: 2),
            TimedSegment(text: "world", start: 2, end: 4),
        ]
        let segs = [
            SpeakerSegment(clusterId: 1, start: 0, end: 2),
            SpeakerSegment(clusterId: 2, start: 2, end: 4),
        ]
        let out = SpeakerAlignment.assignSpeakers(words: words, speakerSegments: segs)
        XCTAssertEqual(out.map(\.speaker), [.remote(1), .remote(2)])
        XCTAssertEqual(out.map(\.text), ["hello", "world"])
    }

    func testStraddleTieGoesToLowerClusterId() {
        let words = [TimedSegment(text: "x", start: 1, end: 3)]
        let segs = [
            SpeakerSegment(clusterId: 2, start: 2, end: 5),
            SpeakerSegment(clusterId: 1, start: 0, end: 2),
        ]
        let out = SpeakerAlignment.assignSpeakers(words: words, speakerSegments: segs)
        XCTAssertEqual(out.map(\.speaker), [.remote(1)])
    }

    func testZeroOverlapFallsBackToNearestMidpoint() {
        let words = [TimedSegment(text: "late", start: 10, end: 11)]
        let segs = [
            SpeakerSegment(clusterId: 1, start: 0, end: 2),
            SpeakerSegment(clusterId: 2, start: 3, end: 5),
        ]
        let out = SpeakerAlignment.assignSpeakers(words: words, speakerSegments: segs)
        XCTAssertEqual(out.map(\.speaker), [.remote(2)])
    }

    func testNoSpeakerSegmentsAssignsSingleUnknownCluster() {
        let words = [TimedSegment(text: "a", start: 0, end: 1)]
        let out = SpeakerAlignment.assignSpeakers(words: words, speakerSegments: [])
        XCTAssertEqual(out.map(\.speaker), [.remote(1)])
    }

    func testEmptyWords() {
        let out = SpeakerAlignment.assignSpeakers(
            words: [], speakerSegments: [SpeakerSegment(clusterId: 1, start: 0, end: 1)])
        XCTAssertTrue(out.isEmpty)
    }

    func testMergeConsecutiveSameSpeaker() {
        let segs = [
            TranscriptSegment(speaker: .me, start: 0, end: 2, text: "a"),
            TranscriptSegment(speaker: .me, start: 2, end: 4, text: "b"),
            TranscriptSegment(speaker: .remote(1), start: 4, end: 6, text: "c"),
        ]
        let merged = SpeakerAlignment.mergeConsecutiveTurns(segs)
        XCTAssertEqual(merged, [
            TranscriptSegment(speaker: .me, start: 0, end: 4, text: "a b"),
            TranscriptSegment(speaker: .remote(1), start: 4, end: 6, text: "c"),
        ])
    }

    func testMergeEmptyAndSingle() {
        XCTAssertTrue(SpeakerAlignment.mergeConsecutiveTurns([]).isEmpty)
        let one = [TranscriptSegment(speaker: .me, start: 0, end: 1, text: "x")]
        XCTAssertEqual(SpeakerAlignment.mergeConsecutiveTurns(one), one)
    }

    func testMergeThreePlusConsecutiveSameSpeaker() {
        let segs = [
            TranscriptSegment(speaker: .remote(1), start: 0, end: 1, text: "a"),
            TranscriptSegment(speaker: .remote(1), start: 1, end: 2, text: "b"),
            TranscriptSegment(speaker: .remote(1), start: 2, end: 3, text: "c"),
            TranscriptSegment(speaker: .me, start: 3, end: 4, text: "d"),
        ]
        let merged = SpeakerAlignment.mergeConsecutiveTurns(segs)
        XCTAssertEqual(merged, [
            TranscriptSegment(speaker: .remote(1), start: 0, end: 3, text: "a b c"),
            TranscriptSegment(speaker: .me, start: 3, end: 4, text: "d"),
        ])
    }

    func testMergeSkipsEmptyTextNoDoubleSpace() {
        let segs = [
            TranscriptSegment(speaker: .me, start: 0, end: 1, text: "hello"),
            TranscriptSegment(speaker: .me, start: 1, end: 2, text: ""),
            TranscriptSegment(speaker: .me, start: 2, end: 3, text: "world"),
        ]
        let merged = SpeakerAlignment.mergeConsecutiveTurns(segs)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].text, "hello world")
    }

    func testZeroDurationWordUsesMidpointFallback() {
        // start == end -> overlap always 0 -> nearest midpoint. word at 4.0;
        // cluster1 mid 0.5, cluster2 mid 4.0 -> cluster2.
        let words = [TimedSegment(text: "tick", start: 4, end: 4)]
        let segs = [
            SpeakerSegment(clusterId: 1, start: 0, end: 1),
            SpeakerSegment(clusterId: 2, start: 3, end: 5),
        ]
        let out = SpeakerAlignment.assignSpeakers(words: words, speakerSegments: segs)
        XCTAssertEqual(out.map(\.speaker), [.remote(2)])
    }

    func testMidpointDistanceTieBreaksToLowerClusterId() {
        // word mid 20; cluster1 mid 20 (19..21), cluster3 mid 20 (18..22) -> tie -> lower id 1.
        let words = [TimedSegment(text: "z", start: 20, end: 20)]
        let segs = [
            SpeakerSegment(clusterId: 3, start: 18, end: 22),
            SpeakerSegment(clusterId: 1, start: 19, end: 21),
        ]
        let out = SpeakerAlignment.assignSpeakers(words: words, speakerSegments: segs)
        XCTAssertEqual(out.map(\.speaker), [.remote(1)])
    }
}
