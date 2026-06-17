import SwiftUI

/// A glossy dropdown that matches the light/vibrant theme — a rounded surface button showing the
/// current selection with an accent icon and a chevron, opening a native menu of options. A
/// better-looking replacement for the plain system `Picker`.
struct GlossyMenu<T: Hashable>: View {
    @Binding var selection: T
    let options: [(value: T, label: String)]
    var systemImage: String? = nil
    var minWidth: CGFloat = 180

    private var currentLabel: String {
        options.first { $0.value == selection }?.label ?? ""
    }

    var body: some View {
        Menu {
            ForEach(options, id: \.value) { opt in
                Button {
                    selection = opt.value
                } label: {
                    if opt.value == selection {
                        Label(opt.label, systemImage: "checkmark")
                    } else {
                        Text(opt.label)
                    }
                }
            }
        } label: {
            HStack(spacing: Spacing.sm) {
                if let systemImage {
                    Image(systemName: systemImage).foregroundStyle(Theme.accent)
                }
                Text(currentLabel)
                    .font(.label).foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: Spacing.sm)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2).foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm + 2)
            .frame(minWidth: minWidth)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(Theme.surface))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .stroke(Theme.hairline, lineWidth: 1))
            .shadow(color: Theme.shadow, radius: 4, y: 1)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .clickableCursor()
    }
}
