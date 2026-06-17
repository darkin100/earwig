import AppKit
import SwiftUI

/// Settings categories, shown as a left rail (the window is wide enough to give each its
/// own page rather than one long scroll).
enum SettingsTab: String, CaseIterable, Identifiable {
    case recording, transcription, speakers, summary, storage, setup

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recording: return "Recording"
        case .transcription: return "Transcription"
        case .speakers: return "Speakers"
        case .summary: return "Summary"
        case .storage: return "Storage"
        case .setup: return "Setup"
        }
    }

    var symbol: String {
        switch self {
        case .recording: return "mic"
        case .transcription: return "waveform"
        case .speakers: return "person.2"
        case .summary: return "sparkles"
        case .storage: return "internaldrive"
        case .setup: return "gearshape"
        }
    }
}

/// The Settings section: transparency about the on-device tech plus the tunable
/// config knobs. Custom "section card" blocks are used instead of `Form` so the
/// ClearRoute dark theme stays consistent.
struct SettingsView: View {
    @Bindable var store: SettingsStore

    @State private var tab: SettingsTab = .recording
    @State private var justSaved = false
    @State private var savedResetTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 0) {
            categorySidebar
                .frame(width: 210)
            Rectangle().fill(Theme.hairline).frame(width: 1)
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.xl) {
                        Text(tab.title)
                            .font(.pageTitle)
                            .foregroundStyle(Theme.textPrimary)
                        GlossyCard {
                            tabContent
                        }
                    }
                    .padding(Spacing.xl)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                footer
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
    }

    private var categorySidebar: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Settings")
                .font(.rowTitle)
                .foregroundStyle(Theme.textPrimary)
                .padding(.bottom, Spacing.sm)
            ForEach(SettingsTab.allCases) { categoryRow($0) }
            Spacer(minLength: 0)
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.bg)
    }

    private func categoryRow(_ t: SettingsTab) -> some View {
        let selected = tab == t
        return Button { tab = t } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: t.symbol).frame(width: 18)
                Text(t.title)
                Spacer()
            }
            .font(.label).fontWeight(selected ? .semibold : .regular)
            .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
            .padding(.horizontal, Spacing.md).padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(selected ? Theme.elevated : Color.clear))
            .overlay(alignment: .leading) {
                // Thin teal leading bar marks the selected row (one restrained accent).
                RoundedRectangle(cornerRadius: 1)
                    .fill(selected ? Theme.accent : Color.clear)
                    .frame(width: 2.5)
                    .padding(.vertical, Spacing.xs)
            }
        }
        .buttonStyle(.plain)
        .clickableCursor()
    }

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .recording: recordingSection
        case .transcription: transcriptionSection
        case .speakers: speakerSection
        case .summary: SummarySettingsView(store: store)
        case .storage: storageSection
        case .setup: setupSection
        }
    }

    private var footer: some View {
        HStack {
            saveRow
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.md)
        .overlay(Hairline(), alignment: .top)
    }

    // MARK: - Transcription

    private var transcriptionSection: some View {
        section("Transcription") {
            infoText("**Whisper large-v3** — WhisperKit, CoreML, on-device. VAD chunking enabled.")
            row("Language") {
                TextField("Locale identifier", text: $store.config.localeIdentifier)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 180)
            }
            caption("A BCP-47 / locale identifier, e.g. en_GB or en_US.")
        }
    }

    // MARK: - Speaker identification

    private var speakerSection: some View {
        section("Speaker identification") {
            infoText("Diarization: **FluidAudio** — pyannote community-1 + WeSpeaker (CoreML, on-device). Recognition: local voiceprint registry.")
            Toggle("Speaker diarization", isOn: $store.config.enableDiarization)
                .tint(Theme.accent)
            slider("Clustering threshold", value: $store.config.clusteringThreshold,
                   range: 0.4 ... 0.9,
                   note: "Lower = more speakers; higher = fewer.")
            slider("Cluster merge threshold", value: $store.config.clusterMergeThreshold,
                   range: 0.5 ... 0.95,
                   note: "How alike two clusters must be to merge.")
            slider("Voice match threshold", value: $store.config.voiceMatchThreshold,
                   range: 0.4 ... 0.9,
                   note: "How close a voice must be to a saved person.")
            slider("Minimum speaker seconds", value: $store.config.minSpeakerSeconds,
                   range: 0 ... 15,
                   note: "Folds tiny splinter speakers below this many seconds.")
        }
    }

    // MARK: - Recording

    private var recordingSection: some View {
        section("Recording") {
            Toggle("Keep audio after transcription", isOn: $store.config.keepAudio)
                .tint(Theme.accent)
            Toggle("Save speaker voiceprints", isOn: $store.config.keepSpeakerEmbeddings)
                .tint(Theme.accent)
        }
    }

    // MARK: - Storage

    private var storageSection: some View {
        section("Storage") {
            row("Notes folder") {
                Text(store.config.notesFolder)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Button {
                NSWorkspace.shared.open(store.config.notesFolderURL)
            } label: {
                Label("Open Notes Folder", systemImage: "folder")
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }

    // MARK: - Setup

    private var setupSection: some View {
        section("Setup") {
            infoText("Re-run the welcome flow to re-check permissions or re-download the on-device models.")
            Button {
                NotificationCenter.default.post(name: .earwigRerunOnboarding, object: nil)
            } label: {
                Label("Re-run setup", systemImage: "sparkles")
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }

    // MARK: - Save

    private var saveRow: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Button {
                store.save()
                ToastCenter.shared.success("Settings saved")
                justSaved = true
                savedResetTask?.cancel()
                savedResetTask = Task {
                    try? await Task.sleep(for: .seconds(1.6))
                    guard !Task.isCancelled else { return }
                    justSaved = false
                }
            } label: {
                if justSaved {
                    Label("Saved", systemImage: "checkmark")
                } else {
                    Text("Save")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .animation(.smooth(duration: 0.2), value: justSaved)
            Text("Changes apply to new recordings.")
                .font(.captionText)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Building blocks

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        FlatSection(title, content: content)
    }

    private func row(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        FieldRow(title, trailing: content)
    }

    private func slider(_ title: String, value: Binding<Double>,
                        range: ClosedRange<Double>, note: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text(title)
                    .font(.label)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(value.wrappedValue, format: .number.precision(.fractionLength(2)))
                    .font(.captionText).monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }
            Slider(value: value, in: range)
                .tint(Theme.accent)
            Text(note)
                .font(.captionText)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private func infoText(_ markdown: String) -> some View {
        Text(.init(markdown))
            .font(.bodyText)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.captionText)
            .foregroundStyle(Theme.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
