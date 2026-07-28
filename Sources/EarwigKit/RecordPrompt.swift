import AppKit

/// A small floating panel in the top-right corner of the screen asking whether
/// to record the meeting that was just detected.
final class RecordPrompt {
    private var panel: NSPanel?
    private var dismissTimer: Timer?

    var isVisible: Bool { panel != nil }

    func show(
        apps: [String], meetingTitle: String? = nil,
        onRecord: @escaping () -> Void, onDismiss: @escaping () -> Void
    ) {
        dismiss()

        let width: CGFloat = 320
        let height: CGFloat = 120
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false

        let content = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))

        let icon = NSImageView(frame: NSRect(x: 16, y: height - 48, width: 24, height: 24))
        icon.image = NSImage(systemSymbolName: "ear.badge.waveform", accessibilityDescription: "Earwig")
        icon.contentTintColor = .systemRed
        content.addSubview(icon)

        // With a derived meeting title, lead with it; the generic header
        // becomes the secondary line.
        let title = NSTextField(labelWithString: meetingTitle ?? "Meeting detected")
        title.font = .boldSystemFont(ofSize: 14)
        title.lineBreakMode = .byTruncatingTail
        title.toolTip = meetingTitle
        title.frame = NSRect(x: 48, y: height - 44, width: width - 60, height: 20)
        content.addSubview(title)

        let detailText = meetingTitle == nil
            ? apps.joined(separator: ", ")
            : "Meeting detected — " + apps.joined(separator: ", ")
        let detail = NSTextField(labelWithString: detailText)
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingTail
        detail.frame = NSRect(x: 48, y: height - 62, width: width - 60, height: 16)
        content.addSubview(detail)

        let recordButton = NSButton(title: "Record", target: nil, action: nil)
        recordButton.bezelStyle = .rounded
        recordButton.keyEquivalent = "\r"
        recordButton.frame = NSRect(x: width - 100, y: 12, width: 84, height: 30)
        content.addSubview(recordButton)

        let ignoreButton = NSButton(title: "Ignore", target: nil, action: nil)
        ignoreButton.bezelStyle = .rounded
        ignoreButton.frame = NSRect(x: width - 184, y: 12, width: 80, height: 30)
        content.addSubview(ignoreButton)

        let recordAction = ActionTrampoline { [weak self] in
            self?.dismiss()
            onRecord()
        }
        let ignoreAction = ActionTrampoline { [weak self] in
            self?.dismiss()
            onDismiss()
        }
        recordButton.target = recordAction
        recordButton.action = #selector(ActionTrampoline.fire)
        ignoreButton.target = ignoreAction
        ignoreButton.action = #selector(ActionTrampoline.fire)
        // Keep trampolines alive for the lifetime of the panel.
        objc_setAssociatedObject(panel, &AssocKeys.record, recordAction, .OBJC_ASSOCIATION_RETAIN)
        objc_setAssociatedObject(panel, &AssocKeys.ignore, ignoreAction, .OBJC_ASSOCIATION_RETAIN)

        panel.contentView = content

        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: frame.maxX - width - 16,
                y: frame.maxY - height - 16
            ))
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

private enum AssocKeys {
    static var record: UInt8 = 0
    static var ignore: UInt8 = 0
}

final class ActionTrampoline: NSObject {
    private let handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler }
    @objc func fire() { handler() }
}
