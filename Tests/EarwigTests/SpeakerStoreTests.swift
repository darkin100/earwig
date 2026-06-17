import XCTest
@testable import Earwig

final class SpeakerStoreTests: XCTestCase {
    func testRoundTripAllLabelCases() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("earwig-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("m.speakers.json")
        let profiles = [
            SpeakerProfile(label: .me, embedding: nil, speechSeconds: 1),
            SpeakerProfile(label: .others, embedding: [0.5], speechSeconds: 2),
            SpeakerProfile(label: .remote(3), embedding: [0.1, 0.9], speechSeconds: 3.25),
        ]
        try SpeakerStore.write(profiles, meeting: "m", to: url)
        let read = try SpeakerStore.read(from: url)
        XCTAssertEqual(read.map(\.label), [.me, .others, .remote(3)])
        XCTAssertEqual(read[2].speechSeconds, 3.25, accuracy: 0.0001)
    }

    func testReadsTaggedNamedLabel() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("earwig-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("named.speakers.json")
        let json = """
        { "meeting": "m", "speakers": [ { "label": { "kind": "named", "name": "Cecile" }, "speechSeconds": 4, "embedding": [0.1] } ] }
        """.data(using: .utf8)!
        try json.write(to: url)
        let read = try SpeakerStore.read(from: url)
        XCTAssertEqual(read[0].label, .named("Cecile"))
    }

    /// Names matching reserved display strings used to round-trip to the wrong case
    /// ("Others" -> .others, "Speaker 3" -> .remote(3)). The tagged form keeps them exact.
    func testReservedLikeNamesRoundTripExactly() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("earwig-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("collide.speakers.json")
        let profiles = [
            SpeakerProfile(label: .named("Others"), embedding: [0.1], speechSeconds: 1),
            SpeakerProfile(label: .named("Speaker 3"), embedding: [0.2], speechSeconds: 2),
            SpeakerProfile(label: .named("Me"), embedding: [0.3], speechSeconds: 3),
        ]
        try SpeakerStore.write(profiles, meeting: "m", to: url)
        let read = try SpeakerStore.read(from: url)
        XCTAssertEqual(read.map(\.label), [.named("Others"), .named("Speaker 3"), .named("Me")])
    }

    func testRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("earwig-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("meeting-x.speakers.json")

        let profiles = [
            SpeakerProfile(label: .remote(1), embedding: [0.1, 0.2, 0.3], speechSeconds: 12.5),
            SpeakerProfile(label: .me, embedding: nil, speechSeconds: 5),
        ]
        try SpeakerStore.write(profiles, meeting: "meeting-x", to: url)

        let read = try SpeakerStore.read(from: url)
        XCTAssertEqual(read.count, 2)
        XCTAssertEqual(read[0].label, .remote(1))
        XCTAssertEqual(read[0].embedding, [0.1, 0.2, 0.3])
        XCTAssertEqual(read[0].speechSeconds, 12.5, accuracy: 0.0001)
        XCTAssertEqual(read[1].label, .me)
        XCTAssertNil(read[1].embedding)
    }
}
