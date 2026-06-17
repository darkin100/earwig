import SwiftUI

/// The onboarding summary-setup step: pick the engine (Ollama or Apple Intelligence) and get
/// it ready — install/pull for Ollama, or confirm Apple availability. Optional: the user can
/// Finish without it and set summaries up later in Settings. Reuses `SummarySettingsView` so
/// onboarding and Settings stay in sync.
struct OnboardingSummaryView: View {
    let store: SettingsStore
    let ollama: OllamaState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Set up summaries")
                    .font(.title2).fontWeight(.bold)
                    .foregroundStyle(Theme.textPrimary)
                Text("Earwig can summarise each meeting on-device. Choose an engine and get it ready — this is optional, and you can change it anytime in Settings.")
                    .font(.bodyText).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ScrollView { GlossyCard { SummarySettingsView(store: store, ollama: ollama) } }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
