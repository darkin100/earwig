import XCTest
@testable import Earwig

@MainActor
final class OnboardingStateTests: XCTestCase {
    /// A fresh, non-shared instance so tests don't stomp the app's singleton.
    private func makeState() -> OnboardingState {
        let s = OnboardingState.shared
        s.reset()
        return s
    }

    func testRequiredPermissionsGate() {
        let s = makeState()
        XCTAssertFalse(s.canContinueFromPermissions)
        s.microphone = .granted
        XCTAssertFalse(s.canContinueFromPermissions)   // system audio still pending
        s.systemAudio = .granted
        XCTAssertTrue(s.canContinueFromPermissions)     // speech optional
        s.speech = .denied
        XCTAssertTrue(s.canContinueFromPermissions)
    }

    func testAdvanceWalksStepsAndStops() {
        let s = makeState()
        XCTAssertEqual(s.step, .welcome)
        s.advance(); XCTAssertEqual(s.step, .permissions)
        s.advance(); XCTAssertEqual(s.step, .models)
        s.advance(); XCTAssertEqual(s.step, .summary)
        s.advance(); XCTAssertEqual(s.step, .done)
        s.advance(); XCTAssertEqual(s.step, .done)       // clamps at the last step
    }

    func testModelProgressMapping() {
        let s = makeState()
        XCTAssertEqual(s.modelProgress, 0, accuracy: 0.0001)
        XCTAssertFalse(s.modelsReady)
        s.modelPhase = .downloading(0.6)
        XCTAssertEqual(s.modelProgress, 0.6, accuracy: 0.0001)
        s.modelPhase = .finished
        XCTAssertEqual(s.modelProgress, 1, accuracy: 0.0001)
        XCTAssertTrue(s.modelsReady)
        s.modelPhase = .failed("boom")
        XCTAssertEqual(s.modelProgress, 0, accuracy: 0.0001)
        XCTAssertFalse(s.modelsReady)
    }
}
