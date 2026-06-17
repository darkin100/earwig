import SwiftUI

/// The glossy gradient primary action — indigo→purple fill, white text, soft shadow and a
/// subtle top highlight. The hero control on a screen (Record, Save, Generate, onboarding).
struct PrimaryButtonStyle: ButtonStyle {
    enum Size { case regular, compact }
    /// `.compact` is for inline controls (e.g. Regenerate) so they sit lighter next to body text.
    var size: Size = .regular

    private var hPad: CGFloat { size == .compact ? Spacing.md : Spacing.lg }
    private var vPad: CGFloat { size == .compact ? Spacing.sm : Spacing.md }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(size == .compact ? .captionText.weight(.semibold) : .label)
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, hPad)
            .padding(.vertical, vPad)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(Theme.primaryGradient)
                    .overlay(
                        // Glossy top highlight.
                        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                            .fill(.white.opacity(0.18))
                            .blur(radius: 4)
                            .mask(LinearGradient(colors: [.white, .clear],
                                                 startPoint: .top, endPoint: .center))
                    )
            )
            .shadow(color: Theme.accent.opacity(size == .compact ? 0.25 : 0.35),
                    radius: size == .compact ? 6 : 10, y: size == .compact ? 2 : 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.smooth(duration: 0.15), value: configuration.isPressed)
            .clickableCursor()
    }
}

/// Secondary control — a soft, tinted pill in the control's role colour (accent by default, or
/// e.g. red for destructive). Tinting it instead of a white bordered button makes it feel native
/// to the app's accent palette rather than a generic macOS button.
struct SecondaryButtonStyle: ButtonStyle {
    /// Tint the label + fill (e.g. red for destructive). Defaults to accent.
    var role: Color = Theme.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.label.weight(.medium))
            .foregroundStyle(role)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(role.opacity(configuration.isPressed ? 0.20 : 0.12)))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.smooth(duration: 0.15), value: configuration.isPressed)
            .clickableCursor()
    }
}
