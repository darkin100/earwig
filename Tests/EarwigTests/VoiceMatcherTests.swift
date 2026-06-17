import XCTest
@testable import Earwig

final class VoiceMatcherTests: XCTestCase {
    func testCosineIdenticalIsOne() {
        XCTAssertEqual(VoiceMatcher.cosineSimilarity([1, 2, 3], [1, 2, 3]), 1, accuracy: 0.0001)
    }

    func testCosineOrthogonalIsZero() {
        XCTAssertEqual(VoiceMatcher.cosineSimilarity([1, 0], [0, 1]), 0, accuracy: 0.0001)
    }

    func testCosineOppositeIsMinusOne() {
        XCTAssertEqual(VoiceMatcher.cosineSimilarity([1, 0], [-1, 0]), -1, accuracy: 0.0001)
    }

    func testCosineZeroVectorIsZero() {
        XCTAssertEqual(VoiceMatcher.cosineSimilarity([0, 0], [1, 1]), 0, accuracy: 0.0001)
        XCTAssertEqual(VoiceMatcher.cosineSimilarity([1, 1], []), 0, accuracy: 0.0001)
    }

    func testBestMatchAboveThreshold() {
        let candidates: [[[Float]]] = [[[1.0, 0.0]], [[0.0, 1.0]]]
        let r = VoiceMatcher.bestMatch([0.99, 0.01], among: candidates, threshold: 0.8)
        XCTAssertEqual(r?.index, 0)
        XCTAssertNotNil(r)
    }

    func testBestMatchBelowThresholdIsNil() {
        let candidates: [[[Float]]] = [[[1.0, 0.0]]]
        XCTAssertNil(VoiceMatcher.bestMatch([0.0, 1.0], among: candidates, threshold: 0.5))
    }

    func testBestMatchUsesBestSamplePerIdentity() {
        let candidates: [[[Float]]] = [[[0.0, 1.0], [1.0, 0.0]]]
        let r = VoiceMatcher.bestMatch([1.0, 0.0], among: candidates, threshold: 0.9)
        XCTAssertEqual(r?.index, 0)
    }

    func testMergeClustersGroupsSimilar() {
        let groups = VoiceMatcher.mergeClusters([[1, 0], [1, 0], [0, 1]], threshold: 0.9)
        XCTAssertEqual(Set(groups.map { Set($0) }), [Set([0, 1]), Set([2])])
    }

    func testMergeClustersTransitive() {
        let groups = VoiceMatcher.mergeClusters([[1, 0], [0.9, 0.1], [0.8, 0.2]], threshold: 0.95)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(Set(groups[0]), Set([0, 1, 2]))
    }

    func testMergeClustersEmpty() {
        XCTAssertTrue(VoiceMatcher.mergeClusters([], threshold: 0.5).isEmpty)
    }

    func testCentroidEmptyIsNil() {
        XCTAssertNil(VoiceMatcher.centroid(of: [], weights: []))
        XCTAssertNil(VoiceMatcher.centroid(of: [[0, 0]], weights: [1]))   // zero-magnitude only
    }

    func testCentroidIsUnitLengthAndAveragesDirection() {
        // Two embeddings either side of the x axis average to point along x, unit length.
        let c = VoiceMatcher.centroid(of: [[1, 1], [1, -1]], weights: [1, 1])!
        XCTAssertEqual(c[0], 1, accuracy: 0.0001)
        XCTAssertEqual(c[1], 0, accuracy: 0.0001)
    }

    func testCentroidIsDurationWeighted() {
        // A long segment pointing +y should dominate a short one pointing +x, so the
        // centroid leans toward +y.
        let c = VoiceMatcher.centroid(of: [[1, 0], [0, 1]], weights: [1, 9])!
        XCTAssertGreaterThan(c[1], c[0])
    }

    func testCentroidSkipsZeroWeightAndMismatchedLength() {
        // Zero-weight and wrong-length vectors are ignored; result follows the +x vector.
        let c = VoiceMatcher.centroid(of: [[1, 0], [0, 1], [5, 5, 5]], weights: [2, 0, 3])!
        XCTAssertEqual(c[0], 1, accuracy: 0.0001)
        XCTAssertEqual(c[1], 0, accuracy: 0.0001)
    }
}
