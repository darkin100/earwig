import XCTest
@testable import Earwig

final class IdentityResolverTests: XCTestCase {
    private func cluster(_ key: String, _ emb: [Float], speech: Double, start: Double) -> ResolvableCluster {
        ResolvableCluster(key: key, embedding: emb, speechSeconds: speech, firstStart: start)
    }

    func testTwoStreamsSameVoiceMergeToOneIdentity() {
        let clusters = [
            cluster("mic#1", [1, 0], speech: 5, start: 0),
            cluster("sys#1", [0.99, 0.01], speech: 4, start: 1),
        ]
        let res = IdentityResolver.resolve(
            clusters: clusters, registry: VoiceRegistry(), mergeThreshold: 0.9, matchThreshold: 0.8)
        XCTAssertEqual(res.labelByKey["mic#1"], .remote(1))
        XCTAssertEqual(res.labelByKey["sys#1"], .remote(1))
        XCTAssertEqual(res.profiles.count, 1)
    }

    func testFoldsSplinterClusterIntoNearestSubstantialSpeaker() {
        // A 1s splinter close to a big speaker should fold into it, not become its own speaker.
        let clusters = [
            cluster("a", [1, 0], speech: 60, start: 0),       // substantial speaker A
            cluster("b", [0, 1], speech: 60, start: 5),       // substantial speaker B
            cluster("c", [0.98, 0.02], speech: 1, start: 30), // splinter, looks like A
        ]
        let res = IdentityResolver.resolve(
            clusters: clusters, registry: VoiceRegistry(),
            mergeThreshold: 0.95, matchThreshold: 0.99, minSpeakerSeconds: 5)
        XCTAssertEqual(res.profiles.count, 2)               // splinter folded away
        XCTAssertEqual(res.labelByKey["c"], res.labelByKey["a"])  // folded into A
        XCTAssertNotEqual(res.labelByKey["a"], res.labelByKey["b"])
    }

    func testKeepsBriefButDistinctSecondSpeaker() {
        // A 3s cluster with a DIFFERENT voiceprint from the big speaker is a real second
        // person who only spoke briefly — not a splinter. It must survive the fold.
        let clusters = [
            cluster("a", [1, 0], speech: 60, start: 0),   // substantial speaker A
            cluster("b", [0, 1], speech: 3, start: 30),   // brief, distinct voice
        ]
        let res = IdentityResolver.resolve(
            clusters: clusters, registry: VoiceRegistry(),
            mergeThreshold: 0.7, matchThreshold: 0.99, minSpeakerSeconds: 5)
        XCTAssertEqual(res.profiles.count, 2)
        XCTAssertNotEqual(res.labelByKey["a"], res.labelByKey["b"])
    }

    func testNoFoldingWhenMinSpeakerSecondsZero() {
        let clusters = [
            cluster("a", [1, 0], speech: 60, start: 0),
            cluster("c", [0, 1], speech: 1, start: 30),
        ]
        let res = IdentityResolver.resolve(
            clusters: clusters, registry: VoiceRegistry(),
            mergeThreshold: 0.95, matchThreshold: 0.99, minSpeakerSeconds: 0)
        XCTAssertEqual(res.profiles.count, 2)   // default 0 ⇒ no folding
    }

    func testDistinctVoicesNumberedByFirstAppearance() {
        let clusters = [
            cluster("sys#2", [0, 1], speech: 3, start: 10),
            cluster("sys#1", [1, 0], speech: 3, start: 2),
        ]
        let res = IdentityResolver.resolve(
            clusters: clusters, registry: VoiceRegistry(), mergeThreshold: 0.9, matchThreshold: 0.8)
        XCTAssertEqual(res.labelByKey["sys#1"], .remote(1))
        XCTAssertEqual(res.labelByKey["sys#2"], .remote(2))
    }

    func testRegistryMatchAssignsName() {
        var reg = VoiceRegistry()
        reg.enroll(name: "Cecile", embedding: [0, 1], isMe: false, maxSamples: 5)
        let clusters = [cluster("sys#1", [0.02, 0.99], speech: 3, start: 0)]
        let res = IdentityResolver.resolve(
            clusters: clusters, registry: reg, mergeThreshold: 0.9, matchThreshold: 0.8)
        XCTAssertEqual(res.labelByKey["sys#1"], .named("Cecile"))
    }

    func testIsMeMatchAssignsMe() {
        var reg = VoiceRegistry()
        reg.enroll(name: "Me", embedding: [1, 0], isMe: true, maxSamples: 5)
        let clusters = [cluster("mic#1", [0.99, 0.01], speech: 9, start: 0)]
        let res = IdentityResolver.resolve(
            clusters: clusters, registry: reg, mergeThreshold: 0.9, matchThreshold: 0.8)
        XCTAssertEqual(res.labelByKey["mic#1"], .me)
    }

    func testEmpty() {
        let res = IdentityResolver.resolve(
            clusters: [], registry: VoiceRegistry(), mergeThreshold: 0.9, matchThreshold: 0.8)
        XCTAssertTrue(res.labelByKey.isEmpty)
        XCTAssertTrue(res.profiles.isEmpty)
    }
}
