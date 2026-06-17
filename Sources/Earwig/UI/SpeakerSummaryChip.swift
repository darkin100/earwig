import SwiftUI

/// Compact header control: a row of overlapping speaker avatars with a count summary
/// and a chevron. The whole thing is a button that opens the Speakers panel.
struct SpeakerSummaryChip: View {
    let speakers: [SpeakerInfo]
    let onOpen: () -> Void

    private let maxAvatars = 4

    private var needNamesCount: Int {
        speakers.filter { !$0.isNamed }.count
    }

    private var summaryText: String {
        if needNamesCount > 0 {
            return "\(needNamesCount) need names"
        }
        return "\(speakers.count) \(speakers.count == 1 ? "speaker" : "speakers")"
    }

    private var accessibilityText: String {
        if needNamesCount > 0 {
            return "Speakers, \(needNamesCount) need names"
        }
        return "Speakers, \(speakers.count)"
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: Spacing.sm) {
                avatars
                Text(summaryText)
                    .font(.captionText)
                    .fontWeight(.medium)
                    .foregroundStyle(needNamesCount > 0 ? Theme.amber : Theme.textSecondary)
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs + 1)
            .background(Capsule().fill(Theme.surface))
            .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .clickableCursor()
        .accessibilityLabel(accessibilityText)
    }

    private var avatars: some View {
        let shown = Array(speakers.prefix(maxAvatars))
        let overflow = speakers.count - shown.count
        return HStack(spacing: -6) {
            ForEach(shown) { speaker in
                SpeakerAvatar(label: speaker.label, isNamed: speaker.isNamed, size: 22)
            }
            if overflow > 0 {
                overflowBadge(overflow)
            }
        }
    }

    private func overflowBadge(_ count: Int) -> some View {
        Circle()
            .fill(Theme.elevated)
            .frame(width: 22, height: 22)
            .overlay(
                Text("+\(count)")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.textSecondary)
            )
            .overlay(Circle().stroke(Theme.bg, lineWidth: 1.5))
            .accessibilityHidden(true)
    }
}
