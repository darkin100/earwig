import SwiftUI

/// A circular avatar showing a speaker's initial (or "?" when unnamed). The fill colour
/// is derived deterministically from the label so the same speaker is always the same
/// colour. Decorative — the surrounding row text carries the speaker's name.
struct SpeakerAvatar: View {
    let label: String
    let isNamed: Bool
    var size: CGFloat = 24

    private var initial: String {
        guard isNamed, let first = label.trimmingCharacters(in: .whitespaces).first else {
            return "?"
        }
        return String(first).uppercased()
    }

    /// Stable, non-negative index into the palette derived from the label's characters.
    private var fill: Color {
        let palette = Theme.avatarPalette
        guard !palette.isEmpty else { return Theme.surface }
        let hash = label.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) }
        let index = ((hash % palette.count) + palette.count) % palette.count
        return palette[index]
    }

    var body: some View {
        Circle()
            .fill(fill)
            .frame(width: size, height: size)
            .overlay(
                Text(initial)
                    .font(.system(size: size * 0.44, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .overlay(Circle().stroke(Theme.surface, lineWidth: 1.5))
            .accessibilityHidden(true)
    }
}
