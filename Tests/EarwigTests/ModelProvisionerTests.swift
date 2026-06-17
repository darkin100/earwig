import XCTest
@testable import Earwig

final class ModelProvisionerTests: XCTestCase {
    func testWhisperStageScaledToItsShare() {
        XCTAssertEqual(
            ModelProvisioner.combinedProgress(whisperFraction: 1, diarizationDone: false),
            ModelProvisioner.whisperWeight, accuracy: 0.0001)
        XCTAssertEqual(
            ModelProvisioner.combinedProgress(whisperFraction: 0.5, diarizationDone: false),
            ModelProvisioner.whisperWeight * 0.5, accuracy: 0.0001)
    }

    func testDiarizationFillsRemainderToFull() {
        XCTAssertEqual(
            ModelProvisioner.combinedProgress(whisperFraction: 1, diarizationDone: true),
            1.0, accuracy: 0.0001)
        XCTAssertEqual(
            ModelProvisioner.combinedProgress(whisperFraction: 1, diarizationDone: false),
            1.0 - ModelProvisioner.diarizationWeight, accuracy: 0.0001)
    }

    func testFractionsClamped() {
        XCTAssertEqual(
            ModelProvisioner.combinedProgress(whisperFraction: -1, diarizationDone: false),
            0, accuracy: 0.0001)
        XCTAssertEqual(
            ModelProvisioner.combinedProgress(whisperFraction: 2, diarizationDone: true),
            1.0, accuracy: 0.0001)
    }
}
