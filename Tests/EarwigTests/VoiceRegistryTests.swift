import XCTest
@testable import Earwig

final class VoiceRegistryTests: XCTestCase {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("voices-\(UUID().uuidString).json")
    }

    func testEnrollAndMatch() {
        var reg = VoiceRegistry()
        reg.enroll(name: "Cecile", embedding: [1, 0], isMe: false, maxSamples: 5)
        let m = reg.match([0.98, 0.02], threshold: 0.8)
        XCTAssertEqual(m?.identity.name, "Cecile")
        XCTAssertFalse(m?.identity.isMe ?? true)
    }

    func testMatchBelowThresholdNil() {
        var reg = VoiceRegistry()
        reg.enroll(name: "Cecile", embedding: [1, 0], isMe: false, maxSamples: 5)
        XCTAssertNil(reg.match([0, 1], threshold: 0.5))
    }

    func testEnrollSameNameAppendsAndCaps() {
        var reg = VoiceRegistry()
        for i in 0..<7 { reg.enroll(name: "Me", embedding: [Float(i), 1], isMe: true, maxSamples: 5) }
        XCTAssertEqual(reg.identities.count, 1)
        XCTAssertEqual(reg.identities[0].samples.count, 5)
        XCTAssertTrue(reg.identities[0].isMe)
    }

    func testForget() {
        var reg = VoiceRegistry()
        reg.enroll(name: "Cecile", embedding: [1, 0], isMe: false, maxSamples: 5)
        reg.forget("Cecile")
        XCTAssertTrue(reg.identities.isEmpty)
    }

    func testRoundTrip() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        var reg = VoiceRegistry()
        reg.enroll(name: "Me", embedding: [0.1, 0.2], isMe: true, maxSamples: 5)
        reg.enroll(name: "Cecile", embedding: [0.3, 0.4], isMe: false, maxSamples: 5)
        try reg.save(to: url)
        let loaded = try VoiceRegistry.load(from: url)
        XCTAssertEqual(loaded.identities.count, 2)
        XCTAssertEqual(loaded.match([0.1, 0.2], threshold: 0.9)?.identity.name, "Me")
    }

    func testLoadMissingFileIsEmpty() throws {
        let loaded = try VoiceRegistry.load(from: tempURL())
        XCTAssertTrue(loaded.identities.isEmpty)
    }

    func testEnrollClampsNonPositiveMaxSamples() {
        var reg = VoiceRegistry()
        // maxSamples <= 0 must not trap and must keep at least the newest sample.
        reg.enroll(name: "Me", embedding: [1, 0], isMe: true, maxSamples: 0)
        reg.enroll(name: "Me", embedding: [0, 1], isMe: true, maxSamples: -3)
        XCTAssertEqual(reg.identities.count, 1)
        XCTAssertEqual(reg.identities[0].samples.count, 1)
        XCTAssertEqual(reg.identities[0].samples[0], [0, 1])   // newest kept
    }
}
