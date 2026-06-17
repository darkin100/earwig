import AppKit
import SwiftUI

/// Hosts the first-run onboarding flow in a centered, fixed-size window. The window has no
/// close button — onboarding is mandatory — and invokes `onFinished` when the user
/// completes the model download, so the host can persist the flag and open the main window.
@MainActor
final class OnboardingWindowController {
    private var window: NSWindow?
    private let onFinished: () -> Void

    nonisolated init(onFinished: @escaping () -> Void) {
        self.onFinished = onFinished
    }

    /// The fixed onboarding size (matches `OnboardingView`'s frame).
    private static let size = NSSize(width: 640, height: 600)

    func show() {
        if let window {
            recenter(window)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        OnboardingState.shared.reset()
        let hosting = NSHostingController(
            rootView: OnboardingView(onComplete: { [weak self] in self?.finish() }))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Welcome to Earwig"
        window.styleMask = [.titled, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        // Pin the window to the content size, then centre — otherwise it opens larger than
        // the content and off-centre.
        window.setContentSize(Self.size)
        self.window = window
        recenter(window)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Centre the window on the screen that has the cursor (or the main screen).
    private func recenter(_ window: NSWindow) {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { window.center(); return }
        let origin = NSPoint(
            x: visible.midX - Self.size.width / 2,
            y: visible.midY - Self.size.height / 2)
        window.setFrame(NSRect(origin: origin, size: window.frame.size), display: true)
    }

    private func finish() {
        window?.close()
        window = nil
        onFinished()
    }
}
