import AppKit

/// A borderless floating panel that can still become key. Borderless `NSWindow`/`NSPanel`
/// return `false` for `canBecomeKey` by default, which forces a focus-first click on any
/// control inside — so SwiftUI buttons in the recording pill appear to need two clicks.
/// Combined with the `.nonactivatingPanel` style, becoming key does not activate the app, so
/// the pill stays a true HUD while its buttons act on the first click.
final class HUDPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
