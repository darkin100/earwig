import SwiftUI

/// One segment in a `SegmentedControl`.
struct SegmentItem<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    var symbol: String?
    var badge: Int

    init(_ value: Value, title: String, symbol: String? = nil, badge: Int = 0) {
        self.value = value
        self.title = title
        self.symbol = symbol
        self.badge = badge
    }

    var id: Value { value }
}

/// A flat, theme-native segmented control. The selected segment is marked by a 2px teal
/// underline (the only accent) + primary text; the rest is secondary text on a shared baseline
/// hairline. Replaces both the custom `MeetingTabBar` and the system blue `.pickerStyle(.segmented)`.
struct SegmentedControl<Value: Hashable>: View {
    @Binding var selection: Value
    let items: [SegmentItem<Value>]

    var body: some View {
        HStack(spacing: Spacing.xl) {
            ForEach(items) { segment($0) }
            Spacer(minLength: 0)
        }
        .overlay(Hairline(), alignment: .bottom)
    }

    private func segment(_ item: SegmentItem<Value>) -> some View {
        let selected = selection == item.value
        return Button {
            selection = item.value
        } label: {
            HStack(spacing: Spacing.sm) {
                if let symbol = item.symbol {
                    Image(systemName: symbol)
                }
                Text(item.title)
                if item.badge > 0 {
                    Badge(text: "\(item.badge)")
                }
            }
            .font(.label)
            .fontWeight(selected ? .semibold : .regular)
            .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.vertical, Spacing.sm)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(selected ? Theme.accent : Color.clear)
                    .frame(height: 2)
            }
        }
        .buttonStyle(.plain)
        .clickableCursor()
    }
}
