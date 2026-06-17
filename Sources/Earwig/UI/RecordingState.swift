import Foundation
import Observation

/// Observable recording lifecycle state shared by the HUD and sidebar.
@Observable @MainActor
final class RecordingState {
    enum Phase {
        case idle
        case recording
        case transcribing
        case summarizing
    }

    var phase: Phase = .idle
    var elapsed: TimeInterval = 0 // seconds

    static let shared = RecordingState()
    private init() {}

    var isRecording: Bool { phase == .recording }
    var isActive: Bool { phase != .idle }

    var elapsedLabel: String {
        let s = Int(elapsed)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}
