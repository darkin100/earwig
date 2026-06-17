import AppKit
import SwiftUI

/// Hosts the recording pill in a borderless always-on-top panel, top-right of the main screen.
@MainActor
final class RecordingHUDController {
    private var panel: NSPanel?
    private let actions: RecordingHUDActions

    nonisolated init(actions: RecordingHUDActions) {
        self.actions = actions
    }

    func show() {
        if panel == nil { panel = makePanel() }
        positionTopRight()
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let view = RecordingHUDView(
            onStop: actions.onStop,
            onOpenWindow: actions.onOpenWindow,
            onOpenNotes: actions.onOpenNotes,
            onOpenConfig: actions.onOpenConfig,
            onOpenLog: actions.onOpenLog,
            onQuit: actions.onQuit
        )
        let hosting = NSHostingController(rootView: view)
        // Size the panel to the SwiftUI content's intrinsic size so the capsule's
        // transparent corners show through the borderless, clear-backed panel.
        hosting.view.layoutSubtreeIfNeeded()
        let fitting = hosting.view.fittingSize

        // HUDPanel (not NSPanel) so the borderless panel can become key — otherwise its
        // SwiftUI buttons need a focus-first click while the app is inactive.
        let panel = HUDPanel(contentViewController: hosting)
        panel.styleMask = [.nonactivatingPanel, .borderless]
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.setContentSize(fitting)
        return panel
    }

    private func positionTopRight() {
        guard let panel, let screen = NSScreen.main else { return }
        panel.layoutIfNeeded()
        let size = panel.frame.size
        let vf = screen.visibleFrame
        let x = vf.maxX - size.width - 16
        let y = vf.maxY - size.height - 12
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
