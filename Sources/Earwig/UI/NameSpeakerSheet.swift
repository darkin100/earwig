import SwiftUI

/// A sheet to name a diarized speaker. If you've named people before, they appear as a list you
/// can tap to assign in one click (no retyping) — selecting one enrolls this voice under that
/// existing person. Otherwise (or as well) you can type a brand-new name, or mark them as "me".
struct NameSpeakerSheet: View {
    let meetingID: String
    let speakerLabel: String
    let audioURL: URL?
    let sampleStart: TimeInterval
    let sampleEnd: TimeInterval
    let onChanged: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var errorMessage: String?
    @State private var audio = AudioPlayer.shared
    @State private var people: [VoiceIdentity] = []
    @State private var sampleID = UUID()

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isPlayingSample: Bool { audio.playingID == sampleID }
    private var hasSample: Bool { audioURL != nil && sampleEnd > sampleStart }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Who is “\(speakerLabel)”?")
                    .font(.rowTitle)
                    .foregroundStyle(Theme.textPrimary)
                Text("Naming enrols this voice so Earwig recognises them in future meetings.")
                    .font(.bodyText)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if hasSample { hearButton }

            if !people.isEmpty {
                existingPeople
                orDivider
            }

            newNameField

            if let errorMessage {
                Text(errorMessage)
                    .font(.captionText)
                    .foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("This is me", action: enrollMe)
                    .buttonStyle(SecondaryButtonStyle())
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save", action: { enroll(named: trimmedName) })
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(trimmedName.isEmpty)
            }
        }
        .padding(Spacing.xl)
        .frame(width: 400)
        .background(Theme.surface)
        .task { people = (try? IdentityService.listIdentities(voicesURL: Config.voicesURL)) ?? [] }
        .onDisappear { audio.stop() }
    }

    // MARK: - Existing people (tap to assign)

    private var existingPeople: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader("Someone you've named before")
            ScrollView {
                VStack(spacing: Spacing.xs) {
                    ForEach(people, id: \.name) { person in
                        personRow(person)
                    }
                }
            }
            .frame(maxHeight: people.count > 4 ? 200 : .infinity)
        }
    }

    private func personRow(_ person: VoiceIdentity) -> some View {
        Button {
            enroll(named: person.name)
        } label: {
            HStack(spacing: Spacing.md) {
                SpeakerAvatar(label: person.name, isNamed: true, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: Spacing.sm) {
                        Text(person.name).font(.label).foregroundStyle(Theme.textPrimary)
                        if person.isMe { Badge(text: "Me", style: .dot) }
                    }
                    Text("\(person.samples.count) voiceprint\(person.samples.count == 1 ? "" : "s")")
                        .font(.captionText).foregroundStyle(Theme.textTertiary)
                }
                Spacer(minLength: Spacing.sm)
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(Theme.accent)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(Theme.bg))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .clickableCursor()
        .accessibilityLabel("Assign to \(person.name)")
    }

    private var orDivider: some View {
        HStack(spacing: Spacing.md) {
            Hairline()
            Text("or add a new name")
                .font(.captionText).foregroundStyle(Theme.textTertiary)
                .fixedSize()
            Hairline()
        }
    }

    private var newNameField: some View {
        TextField("New name", text: $name)
            .textFieldStyle(.roundedBorder)
            .font(.bodyText)
            .onSubmit { enroll(named: trimmedName) }
    }

    private var hearButton: some View {
        Button(action: playSample) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: isPlayingSample ? "stop.fill" : "play.fill")
                Text(isPlayingSample ? "Stop" : "Hear this speaker")
            }
        }
        .buttonStyle(SecondaryButtonStyle())
        .accessibilityLabel(isPlayingSample ? "Stop sample" : "Hear this speaker")
    }

    // MARK: - Actions

    private func playSample() {
        guard let audioURL else { return }
        if isPlayingSample {
            audio.stop()
        } else {
            audio.play(url: audioURL, from: sampleStart, to: sampleEnd, id: sampleID)
        }
    }

    /// Enrol this speaker under `name` (existing or new) and re-render the note.
    private func enroll(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let cfg = Config.load()
        do {
            try IdentityService.nameSpeaker(
                meeting: meetingID, label: speakerLabel, name: trimmed,
                notesFolder: cfg.notesFolderURL, voicesURL: Config.voicesURL,
                maxSamples: cfg.maxSamplesPerVoice)
            ToastCenter.shared.success("Named \(trimmed)")
            finish()
        } catch {
            errorMessage = error.localizedDescription
            ToastCenter.shared.error("Couldn't name speaker")
        }
    }

    private func enrollMe() {
        let cfg = Config.load()
        do {
            try IdentityService.enrollMe(
                meeting: meetingID, label: speakerLabel,
                notesFolder: cfg.notesFolderURL, voicesURL: Config.voicesURL,
                maxSamples: cfg.maxSamplesPerVoice)
            ToastCenter.shared.success("Saved as you")
            finish()
        } catch {
            errorMessage = error.localizedDescription
            ToastCenter.shared.error("Couldn't save your voice")
        }
    }

    private func finish() {
        audio.stop()
        NotificationCenter.default.post(name: .earwigMeetingsChanged, object: nil)
        NotificationCenter.default.post(name: .earwigIdentitiesChanged, object: nil)
        onChanged()
        dismiss()
    }
}
