import SwiftUI

/// A small label chip. `neutral` is a subtle grey pill (counts, "Optional"); `dot` is a teal
/// status dot + label used where teal must signal "current/default/me" without a full fill.
/// Replaces the old bright-teal capsule badges.
struct Badge: View {
    enum Style { case neutral, dot }

    let text: String
    var style: Style = .neutral

    var body: some View {
        switch style {
        case .neutral:
            Text(text)
                .font(.captionText)
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xxs)
                .background(Capsule().fill(Theme.elevated))
        case .dot:
            HStack(spacing: Spacing.xs) {
                Circle().fill(Theme.accent).frame(width: 5, height: 5)
                Text(text)
                    .font(.captionText)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}
