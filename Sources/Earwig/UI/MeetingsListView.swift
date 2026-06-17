import SwiftUI

/// The meetings list: a big page title, then day groups — each a glossy white card holding that
/// day's meetings as rows, with a bold relative-day header above it. Vibrant speaker avatars,
/// generous spacing, light & airy.
struct MeetingsListView: View {
    let store: MeetingsStore
    @Binding var selection: Meeting?

    @State private var pendingDelete: Meeting?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                header
                if store.meetings.isEmpty {
                    emptyState
                } else {
                    ForEach(store.byDay) { group in
                        dayGroup(group)
                    }
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.bg)
        .confirmationDialog(
            "Delete \"\(pendingDelete?.title ?? "")\"?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let meeting = pendingDelete else { return }
                pendingDelete = nil
                let ok = store.delete(meeting)
                if selection?.id == meeting.id { selection = nil }
                if ok {
                    ToastCenter.shared.success("Meeting deleted")
                } else {
                    ToastCenter.shared.error("Some files could not be deleted")
                }
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("This permanently deletes the note, transcript and recording. This cannot be undone.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Meetings")
                .font(.pageTitle)
                .foregroundStyle(Theme.textPrimary)
            Text(store.meetings.isEmpty ? "Your transcribed meetings will live here."
                                        : "\(store.meetings.count) meetings")
                .font(.bodyText)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.bottom, Spacing.xs)
    }

    private var emptyState: some View {
        GlossyCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Image(systemName: "waveform")
                    .font(.system(size: 32))
                    .foregroundStyle(Theme.accent)
                Text("No meetings yet")
                    .font(.rowTitle).foregroundStyle(Theme.textPrimary)
                Text("Start a recording and your transcript will appear here once it's done.")
                    .font(.bodyText).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func dayGroup(_ group: DayGroup) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            dayHeader(group)
            GlossyCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(group.meetings.enumerated()), id: \.element.id) { index, meeting in
                        if index > 0 {
                            Hairline().padding(.leading, Spacing.lg)
                        }
                        row(meeting)
                    }
                }
            }
        }
    }

    private func dayHeader(_ group: DayGroup) -> some View {
        let label = DayLabel.relativeLabel(for: group.day, now: Date())
        return HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Text(label)
                .font(.sectionLarge)
                .foregroundStyle(Theme.textPrimary)
            Text(Self.weekday(group.day))
                .font(.bodyText)
                .foregroundStyle(Theme.textTertiary)
            Spacer(minLength: 0)
            Label("\(group.meetings.count) \(group.meetings.count == 1 ? "meeting" : "meetings")",
                  systemImage: "calendar")
                .font(.captionText)
                .labelStyle(.titleAndIcon)
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, Spacing.xs)
    }

    private func row(_ meeting: Meeting) -> some View {
        let isSelected = selection?.id == meeting.id
        return Button {
            selection = meeting
        } label: {
            HStack(alignment: .top, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(meeting.title)
                        .font(.rowTitle)
                        .foregroundStyle(Theme.textPrimary)
                    Text(metaLine(meeting))
                        .font(.captionText)
                        .foregroundStyle(Theme.textTertiary)
                    preview(meeting)
                        .padding(.top, Spacing.xxs)
                }
                Spacer(minLength: Spacing.sm)
                avatars(meeting)
            }
            .padding(Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(isSelected ? Theme.elevated : Color.clear)
                    .padding(.horizontal, Spacing.xs))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .clickableCursor()
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .contextMenu {
            Button(role: .destructive) {
                pendingDelete = meeting
            } label: {
                Label("Delete meeting", systemImage: "trash")
            }
        }
    }

    private func avatars(_ meeting: Meeting) -> some View {
        let shown = Array(meeting.speakers.prefix(3))
        return HStack(spacing: -Spacing.sm) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, name in
                SpeakerAvatar(label: name, isNamed: isNamed(name), size: 30)
            }
        }
    }

    @ViewBuilder
    private func preview(_ meeting: Meeting) -> some View {
        if let tldr = meeting.summaryTLDR, !tldr.isEmpty {
            Text(tldr)
                .font(.bodyText).foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        } else if !meeting.preview.isEmpty {
            Text(meeting.preview)
                .font(.bodyText).foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
        }
    }

    private func isNamed(_ name: String) -> Bool {
        name != "Others" && name.range(of: "^Speaker \\d+$", options: .regularExpression) == nil
    }

    private func metaLine(_ meeting: Meeting) -> String {
        var parts: [String] = [Self.timeFormatter.string(from: meeting.date)]
        if meeting.durationMinutes > 0 {
            parts.append("\(meeting.durationMinutes) min")
        }
        let count = meeting.speakers.count
        if count > 0 {
            parts.append("\(count) speaker\(count == 1 ? "" : "s")")
        }
        return parts.joined(separator: " · ")
    }

    private static func weekday(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEEE"
        return f.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()
}
