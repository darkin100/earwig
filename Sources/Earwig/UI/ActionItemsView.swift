import SwiftUI

/// The Action Items tab: the extracted owner→task list. Empty state when the meeting has no
/// summary yet or the summary produced no action items.
struct ActionItemsView: View {
    let stored: StoredSummary?

    private var items: [ActionItem] { stored?.summary.actionItems ?? [] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                if items.isEmpty {
                    emptyState
                } else {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        if index > 0 { Hairline() }
                        row(item)
                    }
                }
            }
            .padding(Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func row(_ item: ActionItem) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: "circle")
                .font(.bodyText)
                .foregroundStyle(Theme.textTertiary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(item.task)
                    .font(.bodyText).foregroundStyle(Theme.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if let owner = item.owner, !owner.isEmpty {
                    Text(owner).font(.captionText).foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Image(systemName: "checklist").font(.largeTitle).foregroundStyle(Theme.textTertiary)
            Text(stored == nil ? "No summary yet" : "No action items")
                .font(.rowTitle).foregroundStyle(Theme.textPrimary)
            Text(stored == nil
                ? "Generate a summary (Summary tab) to extract action items."
                : "This meeting's summary didn't surface any action items.")
                .font(.bodyText).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, Spacing.sm)
    }
}
