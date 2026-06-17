import SwiftUI

/// A 1px hairline rule used to separate flat sections (replaces boxed-card borders and
/// `Divider().overlay(...)`).
struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(height: 1)
    }
}
