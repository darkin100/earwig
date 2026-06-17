import AppKit
import Foundation
import Observation

/// Enrolled voice identities for the People screen. Reloads on enrollment/forget and app activation.
@Observable @MainActor
final class IdentityStore {
    private(set) var people: [VoiceIdentity] = []

    // Set once on the main actor in init; read only in deinit — no concurrent access.
    nonisolated(unsafe) private var observers: [NSObjectProtocol] = []

    init() {
        reload()
        let center = NotificationCenter.default
        for name in [Notification.Name.earwigIdentitiesChanged, NSApplication.didBecomeActiveNotification] {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reload() }
            }
            observers.append(token)
        }
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    // Guard: re-assigning identical data re-renders mid-click and swallows the tap.
    func reload() {
        let loaded = (try? IdentityService.listIdentities(voicesURL: Config.voicesURL)) ?? []
        guard loaded != people else { return }
        people = loaded
    }
}
