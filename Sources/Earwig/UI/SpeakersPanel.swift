import SwiftUI

/// The Speakers panel popover content: a named section and a "need names" section,
/// each row offering a voice sample to play and an action to name/rename the speaker.
/// Naming is delegated upward via `onAssign`; this view only reads `AudioPlayer.shared`
/// for play/stop state.
struct SpeakersPanel: View {
    let speakers: [SpeakerInfo]
    let audioURL: URL?
    /// Whether naming is possible (the meeting has saved voiceprints).
    let canAssign: Bool
    let onAssign: (SpeakerInfo) -> Void

    @State private var audio = AudioPlayer.shared

    private var named: [SpeakerInfo] {
        speakers.filter { $0.isNamed }
    }

    private var needNames: [SpeakerInfo] {
        speakers.filter { !$0.isNamed }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Hairline()
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    if !needNames.isEmpty {
                        section(title: "Need names", speakers: needNames, isAssign: true)
                    }
                    if !named.isEmpty {
                        section(title: "Named", speakers: named, isAssign: false)
                    }
                    if !canAssign {
                        Text("Voiceprints not saved for this meeting — naming is unavailable.")
                            .font(.captionText)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(Spacing.lg)
            }
            .frame(maxHeight: 380)
        }
        .frame(width: 340)
        .background(Theme.surface)
        .onDisappear {
            audio.stop()
        }
    }

    private var header: some View {
        HStack {
            Text("Speakers")
                .font(.rowTitle)
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Text("\(named.count) of \(speakers.count) named")
                .font(.captionText)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(Spacing.lg)
    }

    @ViewBuilder
    private func section(title: String, speakers: [SpeakerInfo], isAssign: Bool) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title)
            ForEach(speakers) { speaker in
                row(speaker, isAssign: isAssign)
            }
        }
    }

    private func row(_ speaker: SpeakerInfo, isAssign: Bool) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            SpeakerAvatar(label: speaker.label, isNamed: speaker.isNamed, size: 30)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(speaker.label)
                    .font(.label)
                    .fontWeight(isAssign ? .regular : .semibold)
                    .foregroundStyle(Theme.textPrimary)
                if !speaker.snippet.isEmpty {
                    Text(speaker.snippet)
                        .font(.captionText)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                if isAssign {
                    assignButton(speaker)
                        .padding(.top, Spacing.xs)
                }
            }
            Spacer(minLength: Spacing.xs)
            if hasSample(speaker) {
                playButton(speaker)
            }
            if !isAssign {
                renameButton(speaker)
            }
        }
    }

    private func assignButton(_ speaker: SpeakerInfo) -> some View {
        Button {
            onAssign(speaker)
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "person.crop.circle.badge.plus")
                Text("Assign \(speaker.label)")
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(!canAssign)
        .opacity(canAssign ? 1 : 0.4)
        .accessibilityLabel("Assign \(speaker.label)")
    }

    private func renameButton(_ speaker: SpeakerInfo) -> some View {
        Button {
            onAssign(speaker)
        } label: {
            Image(systemName: "pencil")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .buttonStyle(.plain)
        .clickableCursor()
        .disabled(!canAssign)
        .opacity(canAssign ? 1 : 0.4)
        .accessibilityLabel("Rename \(speaker.label)")
    }

    private func playButton(_ speaker: SpeakerInfo) -> some View {
        let isPlaying = audio.playingID == speaker.id
        return Button {
            guard let audioURL else { return }
            if isPlaying {
                audio.stop()
            } else {
                audio.play(url: audioURL, from: speaker.sampleStart, to: speaker.sampleEnd, id: speaker.id)
            }
        } label: {
            Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                .font(.caption)
                .foregroundStyle(isPlaying ? Theme.accent : Theme.textSecondary)
        }
        .buttonStyle(.plain)
        .clickableCursor()
        .accessibilityLabel(isPlaying ? "Stop \(speaker.label) sample" : "Play \(speaker.label) sample")
    }

    /// A speaker has a playable sample when there's audio and a non-empty range.
    private func hasSample(_ speaker: SpeakerInfo) -> Bool {
        audioURL != nil && speaker.sampleEnd > speaker.sampleStart
    }
}
