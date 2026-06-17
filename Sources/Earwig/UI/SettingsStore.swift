import Foundation
import Observation

/// Editable `Config` for the Settings screen. `save()` persists and broadcasts so the app reloads.
@Observable @MainActor
final class SettingsStore {
    var config: Config = Config.load()

    func save() {
        config.save()
        NotificationCenter.default.post(name: .earwigConfigChanged, object: nil)
    }
}
