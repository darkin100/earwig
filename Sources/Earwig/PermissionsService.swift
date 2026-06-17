import AVFoundation
import AppKit
import Speech

/// Resolved authorization for one permission. `denied` folds in `restricted` — both mean
/// "blocked, needs a trip to System Settings".
enum Authorization: Equatable {
    case granted
    case denied
    case notDetermined
}

/// The OS permissions Earwig can request during onboarding.
enum Permission: String, CaseIterable {
    case microphone
    case systemAudio
    case speechRecognition
}

/// Queries and requests every OS permission Earwig needs.
///
/// Mic + Speech have TCC status APIs. System Audio (CoreAudio process tap, macOS 14.4+)
/// has no status API — probed by attempting to create a tap. First probe triggers the
/// prompt and returns `.denied` until the user accepts; re-probe after app reactivates.
enum PermissionsService {
    // MARK: Microphone

    static func microphoneStatus() -> Authorization {
        map(AVCaptureDevice.authorizationStatus(for: .audio))
    }

    static func requestMicrophone() async -> Authorization {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        }
        return microphoneStatus()
    }

    // MARK: Speech recognition (fallback engine only)

    static func speechStatus() -> Authorization {
        map(SFSpeechRecognizer.authorizationStatus())
    }

    static func requestSpeech() async -> Authorization {
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            await withCheckedContinuation { cont in
                SFSpeechRecognizer.requestAuthorization { _ in cont.resume() }
            }
        }
        return speechStatus()
    }

    // MARK: System audio (no status API — probe by creating a tap)

    static func requestSystemAudio() -> Authorization {
        SystemAudioTap.probePermission() ? .granted : .denied
    }

    // MARK: Deep links to System Settings

    /// Opens the Privacy pane for this permission; falls back to Privacy root on old macOS.
    static func openSettings(for permission: Permission) {
        let anchor: String
        switch permission {
        case .microphone: anchor = "Privacy_Microphone"
        case .systemAudio: anchor = "Privacy_AudioCapture"
        case .speechRecognition: anchor = "Privacy_SpeechRecognition"
        }
        let base = "x-apple.systempreferences:com.apple.preference.security"
        let url = URL(string: "\(base)?\(anchor)") ?? URL(string: base)!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Pure status mapping (testable)

    static func map(_ status: AVAuthorizationStatus) -> Authorization {
        switch status {
        case .authorized: return .granted
        case .notDetermined: return .notDetermined
        case .denied, .restricted: return .denied
        @unknown default: return .denied
        }
    }

    static func map(_ status: SFSpeechRecognizerAuthorizationStatus) -> Authorization {
        switch status {
        case .authorized: return .granted
        case .notDetermined: return .notDetermined
        case .denied, .restricted: return .denied
        @unknown default: return .denied
        }
    }
}
