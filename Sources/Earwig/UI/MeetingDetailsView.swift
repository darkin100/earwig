import SwiftUI

/// The Details tab: meeting metadata plus the maintenance actions (Re-transcribe, Copy
/// transcript). Re-transcribe re-runs the pipeline on the saved audio; it's disabled when
/// the audio is no longer available.
struct MeetingDetailsView: View {
    let meeting: Meeting
    let speakerCount: Int
    let stored: StoredSummary?
    let isReprocessing: Bool
    let reprocessError: String?
    let onReprocess: () -> Void
    let onCopyTranscript: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                infoCard
                Hairline()
                actionsCard
            }
            .padding(Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var infoCard: some View {
        FlatSection("Details") {
            ValueRow(label: "Date", value: Self.dateFormatter.string(from: meeting.date))
            ValueRow(label: "Duration", value: meeting.durationMinutes > 0 ? "\(meeting.durationMinutes) min" : "—")
            ValueRow(label: "Source", value: meeting.source)
            ValueRow(label: "Speakers", value: speakerCount > 0 ? "\(speakerCount)" : "—")
            ValueRow(label: "Audio", value: meeting.audioURL != nil ? "Kept" : "Not available")
            if let stored {
                ValueRow(label: "Summary model", value: stored.model)
            }
        }
    }

    private var actionsCard: some View {
        FlatSection("Actions") {
            HStack(spacing: Spacing.sm) {
                Button {
                    onReprocess()
                } label: {
                    HStack(spacing: Spacing.sm) {
                        if isReprocessing { ProgressView().controlSize(.small) }
                        else { Image(systemName: "arrow.clockwise") }
                        Text(isReprocessing ? "Re-transcribing…" : "Re-transcribe")
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(isReprocessing || meeting.audioURL == nil)

                Button("Copy transcript", systemImage: "doc.on.doc", action: onCopyTranscript)
                    .buttonStyle(SecondaryButtonStyle())
            }
            if meeting.audioURL == nil {
                Text("Re-transcribe needs the original audio, which isn’t available for this meeting.")
                    .font(.captionText).foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let reprocessError {
                Text(reprocessError).font(.captionText).foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEEE, MMM d · HH:mm"
        return f
    }()
}
