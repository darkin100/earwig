import SwiftUI

/// A label-left / control-right row used across Settings and Summary panels.
struct FieldRow<Trailing: View>: View {
    let label: String
    @ViewBuilder var trailing: Trailing

    init(_ label: String, @ViewBuilder trailing: () -> Trailing) {
        self.label = label
        self.trailing = trailing()
    }

    var body: some View {
        HStack {
            Text(label)
                .font(.label)
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: Spacing.sm)
            trailing
        }
    }
}

/// A read-only label-left / value-right row (e.g. the meeting Details tab). The label is
/// tertiary, the value primary and selectable.
struct ValueRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
            Text(label)
                .font(.captionText)
                .foregroundStyle(Theme.textTertiary)
            Spacer(minLength: Spacing.sm)
            Text(value)
                .font(.bodyText)
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}
