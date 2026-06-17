import SwiftUI

/// Multi-line text editor with an aligned placeholder. NSTextView adds 5pt line-fragment padding
/// before the first glyph, so the placeholder is inset by pad + 5pt to share the same left edge.
struct PlaceholderTextEditor: View {
    let placeholder: String
    @Binding var text: String
    /// Fixed editor height when `fillsHeight` is false (ignored when it fills).
    var height: CGFloat = 120
    var fillsHeight: Bool = false
    var autoFocus: Bool = false
    var accessibilityLabel: String?

    @FocusState private var focused: Bool

    private let pad: CGFloat = Spacing.sm           // editor inset
    private let lineFragmentPadding: CGFloat = 5    // NSTextView default before the first glyph

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(.bodyText)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.leading, pad + lineFragmentPadding)
                    .padding(.top, pad)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .font(.bodyText)
                .foregroundStyle(Theme.textPrimary)
                .scrollContentBackground(.hidden)
                .focused($focused)
                .padding(.horizontal, pad)
                .padding(.vertical, pad)
                .frame(maxWidth: .infinity, maxHeight: fillsHeight ? .infinity : nil)
                .accessibilityLabel(accessibilityLabel ?? placeholder)
        }
        .frame(height: fillsHeight ? nil : height)
        .frame(maxHeight: fillsHeight ? .infinity : nil)
        .background(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(Theme.elevated.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .stroke(Theme.hairline, lineWidth: 1)
        )
        .onAppear { if autoFocus { focused = true } }
    }
}
