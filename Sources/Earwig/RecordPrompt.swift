import AppKit
import SwiftUI

/// A small floating panel in the top-right corner asking whether to record the detected meeting.
/// Hosts the glossy `RecordPromptView`; uses `HUDPanel` (borderless but key-capable) so the
/// buttons act on the first click while the app is inactive.
final class RecordPrompt {
    private var panel: NSPanel?
    private var dismissTimer: Timer?

    var isVisible: Bool { panel != nil }

    func show(apps: [String], onRecord: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        dismiss()

        let view = RecordPromptView(
            appName: apps.first ?? "A meeting app",
            onRecord: { [weak self] in self?.dismiss(); onRecord() },
            onIgnore: { [weak self] in self?.dismiss(); onDismiss() })

        let hosting = NSHostingController(rootView: view)
        hosting.view.layoutSubtreeIfNeeded()
        let fitting = hosting.view.fittingSize

        let panel = HUDPanel(contentViewController: hosting)
        panel.styleMask = [.nonactivatingPanel, .borderless]
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.setContentSize(fitting)

        if let screen = NSScreen.main {
            let vf = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: vf.maxX - fitting.width - 12, y: vf.maxY - fitting.height - 12))
        }
        panel.orderFrontRegardless()
        self.panel = panel

        // Auto-dismiss after 5 minutes so a missed prompt doesn't linger forever.
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: false) { [weak self] _ in
            self?.dismiss()
            onDismiss()
        }
    }

    func dismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        panel?.orderOut(nil)
        panel = nil
    }
}
