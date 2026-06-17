import SwiftUI

/// The Notes tab: a free-text editor for post-meeting observations. Notes are autosaved by
/// `MeetingDetailView` and folded into the summary prompt on Regenerate.
struct NotesView: View {
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader("Notes")
            PlaceholderTextEditor(
                placeholder: "Jot notes about this meeting. They are included when you regenerate the summary.",
                text: $text,
                fillsHeight: true,
                accessibilityLabel: "Meeting notes")
            Text("Notes are saved automatically and included when you regenerate the summary.")
                .font(.captionText)
                .foregroundStyle(Theme.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
