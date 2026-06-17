import XCTest
@testable import Earwig

final class ConfigTests: XCTestCase {
    func testDecodingOldConfigAppliesNewDefaults() throws {
        let oldJSON = """
        {
          "notesFolder": "/tmp/notes",
          "audioFolder": "/tmp/notes/audio",
          "keepAudio": true,
          "localeIdentifier": "en_GB"
        }
        """.data(using: .utf8)!

        let cfg = try JSONDecoder().decode(Config.self, from: oldJSON)
        XCTAssertEqual(cfg.localeIdentifier, "en_GB")
        XCTAssertTrue(cfg.enableDiarization)
        XCTAssertTrue(cfg.keepSpeakerEmbeddings)
        XCTAssertEqual(cfg.clusteringThreshold, 0.7, accuracy: 0.0001)
        XCTAssertEqual(cfg.minSpeechDuration, 1.0, accuracy: 0.0001)
    }

    func testNewFieldsDecodeWhenPresent() throws {
        let json = """
        {
          "notesFolder": "/tmp/notes",
          "audioFolder": "/tmp/notes/audio",
          "keepAudio": false,
          "localeIdentifier": "en_US",
          "enableDiarization": false,
          "keepSpeakerEmbeddings": false,
          "clusteringThreshold": 0.5,
          "minSpeechDuration": 2.0
        }
        """.data(using: .utf8)!
        let cfg = try JSONDecoder().decode(Config.self, from: json)
        XCTAssertFalse(cfg.enableDiarization)
        XCTAssertFalse(cfg.keepSpeakerEmbeddings)
        XCTAssertEqual(cfg.clusteringThreshold, 0.5, accuracy: 0.0001)
        XCTAssertEqual(cfg.minSpeechDuration, 2.0, accuracy: 0.0001)
    }

    func testOnboardingDefaultsFalseOnOldConfig() throws {
        let oldJSON = """
        { "notesFolder": "/tmp/n", "audioFolder": "/tmp/n/a", "keepAudio": true, "localeIdentifier": "en_GB" }
        """.data(using: .utf8)!
        let cfg = try JSONDecoder().decode(Config.self, from: oldJSON)
        XCTAssertFalse(cfg.hasCompletedOnboarding)
        XCTAssertFalse(Config.defaultConfig.hasCompletedOnboarding)
    }

    func testOnboardingFlagRoundTrips() throws {
        var cfg = Config.defaultConfig
        cfg.hasCompletedOnboarding = true
        let data = try JSONEncoder().encode(cfg)
        let decoded = try JSONDecoder().decode(Config.self, from: data)
        XCTAssertTrue(decoded.hasCompletedOnboarding)
    }

    func testVoiceDefaultsOnOldConfig() throws {
        let oldJSON = """
        { "notesFolder": "/tmp/n", "audioFolder": "/tmp/n/a", "keepAudio": true, "localeIdentifier": "en_GB" }
        """.data(using: .utf8)!
        let cfg = try JSONDecoder().decode(Config.self, from: oldJSON)
        XCTAssertEqual(cfg.voiceMatchThreshold, 0.6, accuracy: 0.0001)
        XCTAssertEqual(cfg.clusterMergeThreshold, 0.7, accuracy: 0.0001)
        XCTAssertEqual(cfg.maxSamplesPerVoice, 5)
    }
}
