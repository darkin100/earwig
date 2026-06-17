import SwiftUI

/// A flat section title: uppercase, tracked, tertiary-coloured — no box. Used at the top of a
/// `FlatSection`.
struct SectionHeader: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title.uppercased())
            .font(.sectionTitle)
            .tracking(0.6)
            .foregroundStyle(Theme.textTertiary)
    }
}
