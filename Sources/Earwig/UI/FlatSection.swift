import SwiftUI

/// A flat, **borderless** content group: an optional `SectionHeader` followed by its content,
/// with no fill, stroke, or corner radius. Sections are separated from siblings by whitespace
/// and `Hairline`s placed by the parent — replacing the old boxed `card()`/`section()` builders.
///
/// Named `FlatSection` (not `Section`) to avoid colliding with SwiftUI's built-in `Section`.
struct FlatSection<Content: View>: View {
    let title: String?
    @ViewBuilder var content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            if let title {
                SectionHeader(title)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
