import AppKit
import Observation

/// Onboarding flow state: current step, permission statuses, model-download progress.
@Observable @MainActor
final class OnboardingState {
    enum Step: Int, CaseIterable {
        case welcome, permissions, models, summary, done
    }

    /// Model download/warm lifecycle. `downloading` carries a [0,1] fraction.
    enum ModelPhase: Equatable {
        case idle
        case downloading(Double)
        case finished
        case failed(String)
    }

    var step: Step = .welcome
    var microphone: Authorization = .notDetermined
    var systemAudio: Authorization = .notDetermined
    var speech: Authorization = .notDetermined
    var modelPhase: ModelPhase = .idle
    // System audio has no status API; only probe (which can trigger the prompt) after explicit attempt.
    private(set) var systemAudioAttempted = false

    static let shared = OnboardingState()
    private init() {}

    // MARK: - Derived (pure)

    var requiredPermissionsGranted: Bool {
        microphone == .granted && systemAudio == .granted
    }

    /// Whether the Permissions step's Continue button is enabled.
    var canContinueFromPermissions: Bool { requiredPermissionsGranted }

    var modelsReady: Bool { modelPhase == .finished }

    var modelProgress: Double {
        switch modelPhase {
        case .idle, .failed: return 0
        case .downloading(let fraction): return fraction
        case .finished: return 1
        }
    }

    func advance() {
        if let next = Step(rawValue: step.rawValue + 1) { step = next }
    }

    func reset() {
        step = .welcome
        microphone = .notDetermined
        systemAudio = .notDetermined
        speech = .notDetermined
        modelPhase = .idle
        systemAudioAttempted = false
    }

    // MARK: - Requests (side-effecting)

    func requestMicrophone() async {
        microphone = await PermissionsService.requestMicrophone()
    }

    func requestSpeech() async {
        speech = await PermissionsService.requestSpeech()
    }

    func requestSystemAudio() {
        systemAudioAttempted = true
        systemAudio = PermissionsService.requestSystemAudio()
    }

    /// Re-probes system audio only if previously attempted — avoids prompting on first appear.
    func refreshStatuses() {
        // Assign only on change — identical values re-render mid-click and swallow the tap.
        let mic = PermissionsService.microphoneStatus()
        if microphone != mic { microphone = mic }
        let sp = PermissionsService.speechStatus()
        if speech != sp { speech = sp }
        if systemAudioAttempted, systemAudio != .granted {
            let sa = PermissionsService.requestSystemAudio()
            if systemAudio != sa { systemAudio = sa }
        }
    }

    func downloadModels() async {
        modelPhase = .downloading(0)
        do {
            try await ModelProvisioner.downloadAndWarm { [weak self] fraction in
                self?.modelPhase = .downloading(fraction)
            }
            modelPhase = .finished
        } catch {
            let detail = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            modelPhase = .failed(detail)
        }
    }
}
