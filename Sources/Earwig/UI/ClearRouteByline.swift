import SwiftUI

/// The "by ClearRoute" parent-brand wordmark — neutral "by Clear" + accent "Route", echoing
/// clearroute.io. Used wherever Earwig should carry the ClearRoute brand.
struct ClearRouteByline: View {
    var body: some View {
        HStack(spacing: 0) {
            Text("by Clear").foregroundStyle(Theme.textTertiary)
            Text("Route").foregroundStyle(Theme.accent)
        }
        .font(.caption2).fontWeight(.semibold)
        .accessibilityLabel("by ClearRoute")
    }
}
