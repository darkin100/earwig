import AppKit
import CoreAudio
import Foundation

/// Polls CoreAudio for "microphone in use" and cross-references running apps
/// that host meetings. When the mic transitions idle -> active while a meeting
/// app is running, fires `onMeetingDetected`.
final class MeetingDetector {
    struct MeetingApp {
        let bundleIDPrefixes: [String]
        let displayName: String
        /// Browsers host Google Meet but also everything else, so they are
        /// lower-confidence signals.
        let isBrowser: Bool
    }

    static let knownApps: [MeetingApp] = [
        MeetingApp(bundleIDPrefixes: ["com.microsoft.teams"], displayName: "Microsoft Teams", isBrowser: false),
        MeetingApp(bundleIDPrefixes: ["com.tinyspeck.slackmacgap"], displayName: "Slack", isBrowser: false),
        MeetingApp(bundleIDPrefixes: ["us.zoom.xos"], displayName: "Zoom", isBrowser: false),
        MeetingApp(bundleIDPrefixes: ["com.google.Chrome"], displayName: "Chrome (Google Meet?)", isBrowser: true),
        MeetingApp(bundleIDPrefixes: ["com.apple.Safari"], displayName: "Safari (Google Meet?)", isBrowser: true),
        MeetingApp(bundleIDPrefixes: ["com.microsoft.edgemac"], displayName: "Edge (Google Meet?)", isBrowser: true),
        MeetingApp(bundleIDPrefixes: ["company.thebrowser.Browser"], displayName: "Arc (Google Meet?)", isBrowser: true),
        MeetingApp(bundleIDPrefixes: ["com.brave.Browser"], displayName: "Brave (Google Meet?)", isBrowser: true),
        MeetingApp(bundleIDPrefixes: ["org.mozilla.firefox"], displayName: "Firefox (Google Meet?)", isBrowser: true),
    ]

    /// Called on the main thread with the display names of candidate meeting apps.
    var onMeetingDetected: (([String]) -> Void)?
    /// When true the detector ignores mic activity (we are the ones using the mic).
    var suspended = false

    private var timer: Timer?
    private var micWasActive = false
    private var lastPromptDate: Date?
    private let promptCooldown: TimeInterval = 90

    func start() {
        micWasActive = micIsActive() // don't fire for a call already in progress at launch
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        Log.info("MeetingDetector started (mic active at launch: \(micWasActive))")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard !suspended else { return }
        let active = micIsActive()
        defer { micWasActive = active }
        guard active, !micWasActive else { return }

        // Mic just became active. Is a meeting app running?
        let candidates = runningMeetingApps()
        guard !candidates.isEmpty else {
            Log.info("Mic became active but no known meeting app is running")
            return
        }
        if let last = lastPromptDate, Date().timeIntervalSince(last) < promptCooldown {
            return
        }
        lastPromptDate = Date()
        Log.info("Meeting detected: \(candidates.joined(separator: ", "))")
        DispatchQueue.main.async { [weak self] in
            self?.onMeetingDetected?(candidates)
        }
    }

    func runningMeetingApps() -> [String] {
        let running = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        var names: [String] = []
        for app in Self.knownApps {
            if running.contains(where: { id in app.bundleIDPrefixes.contains(where: { id.hasPrefix($0) }) }) {
                names.append(app.displayName)
            }
        }
        // Prefer dedicated meeting apps; only mention browsers if no dedicated app matched.
        let dedicated = names.filter { !$0.contains("?") }
        return dedicated.isEmpty ? names : dedicated
    }

    /// True when any process is pulling audio from the default input device.
    func micIsActive() -> Bool {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        guard status == noErr, deviceID != 0 else { return false }

        var running: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &running)
        return status == noErr && running != 0
    }
}
