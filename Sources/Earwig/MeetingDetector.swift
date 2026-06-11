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
        MeetingApp(bundleIDPrefixes: ["net.whatsapp.WhatsApp"], displayName: "WhatsApp", isBrowser: false),
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
        // Don't fire for a call already in progress at launch.
        micWasActive = !Self.meetingAppsUsingMic().isEmpty
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
        // Precise detection: which meeting apps are actively capturing the mic?
        let appsOnMic = Self.meetingAppsUsingMic()
        let active = !appsOnMic.isEmpty
        defer { micWasActive = active }
        guard active, !micWasActive else { return }

        let candidates = appsOnMic
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
        let apps = Self.knownApps.filter { app in
            running.contains(where: { id in app.bundleIDPrefixes.contains(where: { id.hasPrefix($0) }) })
        }
        return Self.preferDedicated(apps).map(\.displayName)
    }

    /// Dedicated meeting apps are a stronger signal than browsers (which could
    /// be using the mic for anything) — only mention browsers when no
    /// dedicated app matched.
    private static func preferDedicated(_ apps: [MeetingApp]) -> [MeetingApp] {
        let dedicated = apps.filter { !$0.isBrowser }
        return dedicated.isEmpty ? apps : dedicated
    }

    /// Display names of known meeting apps that are actively capturing the
    /// microphone right now (per-process attribution, macOS 14.4+).
    static func meetingAppsUsingMic() -> [String] {
        var apps: [MeetingApp] = []
        for bundleID in bundleIDsUsingMic() {
            if let app = knownApps.first(where: { app in
                app.bundleIDPrefixes.contains(where: { bundleID.hasPrefix($0) })
            }), !apps.contains(where: { $0.displayName == app.displayName }) {
                apps.append(app)
            }
        }
        return preferDedicated(apps).map(\.displayName)
    }

    /// Bundle IDs of all processes currently capturing audio input.
    static func bundleIDsUsingMic() -> [String] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size)
        guard status == noErr, size > 0 else { return [] }

        var processes = [AudioObjectID](
            repeating: AudioObjectID(kAudioObjectUnknown),
            count: Int(size) / MemoryLayout<AudioObjectID>.size)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &processes)
        guard status == noErr else { return [] }

        let ownPID = getpid()
        var bundleIDs: [String] = []
        for process in processes where process != kAudioObjectUnknown {
            var running: UInt32 = 0
            var runningSize = UInt32(MemoryLayout<UInt32>.size)
            var runningAddress = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyIsRunningInput,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            guard AudioObjectGetPropertyData(
                process, &runningAddress, 0, nil, &runningSize, &running) == noErr,
                running != 0 else { continue }

            var pid: pid_t = 0
            var pidSize = UInt32(MemoryLayout<pid_t>.size)
            var pidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyPID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            if AudioObjectGetPropertyData(process, &pidAddress, 0, nil, &pidSize, &pid) == noErr,
               pid == ownPID { continue }

            var bundle: CFString = "" as CFString
            var bundleSize = UInt32(MemoryLayout<CFString>.size)
            var bundleAddress = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyBundleID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            let bundleStatus = withUnsafeMutablePointer(to: &bundle) { ptr in
                AudioObjectGetPropertyData(process, &bundleAddress, 0, nil, &bundleSize, ptr)
            }
            if bundleStatus == noErr {
                let id = bundle as String
                if !id.isEmpty { bundleIDs.append(id) }
            }
        }
        return bundleIDs
    }

}
