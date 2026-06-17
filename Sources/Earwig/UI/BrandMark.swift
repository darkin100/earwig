import AppKit
import SwiftUI

/// Earwig's brand lockup: the app logo leads, the **Earwig** product name is the headline,
/// and **ClearRoute** (the parent brand) sits underneath as a secondary "by ClearRoute"
/// mark — echoing clearroute.io's white-"Clear" + teal-"Route" wordmark.
struct BrandMark: View {
    var logoSize: CGFloat = 30
    var titleFont: Font = .title3

    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: logoSize, height: logoSize)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Earwig")
                    .font(titleFont).fontWeight(.bold)
                    .foregroundStyle(Theme.textPrimary)
                byClearRoute
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Earwig by ClearRoute")
    }

    private var byClearRoute: some View {
        HStack(spacing: 0) {
            Text("by Clear").foregroundStyle(Theme.textSecondary)
            Text("Route").foregroundStyle(Theme.accent)
        }
        .font(.caption2).fontWeight(.semibold)
    }
}
