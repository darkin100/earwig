import SwiftUI

extension View {
    /// Shows the macOS pointing-hand cursor while hovering a clickable control.
    /// SwiftUI's plain and custom buttons keep the default arrow cursor on macOS, which
    /// reads as "not clickable"; the link pointer matches the design references and makes
    /// interactive elements feel responsive. Uses the macOS 15 `pointerStyle` API.
    func clickableCursor() -> some View {
        pointerStyle(.link)
    }
}
