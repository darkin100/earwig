import SwiftUI

/// A glossy white card: rounded, hairline-outlined, soft drop shadow. The building block of the
/// light, Apple-like layout (day groups, detail panels, settings sections).
struct GlossyCard<Content: View>: View {
    var padding: CGFloat = Spacing.lg
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(Theme.surface))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .stroke(Theme.hairline, lineWidth: 1))
            .shadow(color: Theme.shadow, radius: 14, y: 5)
    }
}
