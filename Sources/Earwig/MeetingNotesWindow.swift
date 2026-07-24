import AppKit
import SwiftUI

/// The live meeting-notes sidebar: a floating panel docked to the right edge
/// of the screen while a recording is running. Text typed here is attached to
/// the transcript note when the call ends.
final class MeetingNotesController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private let model = MeetingNotesModel()

    /// Invoked by the sidebar's Stop button; the AppDelegate wires this to
    /// "stop recording and process".
    var onStop: (() -> Void)?

    var isOpen: Bool { panel?.isVisible ?? false }

    func open(meetingTitle: String?) {
        model.title = meetingTitle ?? "Meeting notes"
        if panel == nil {
            let hosting = NSHostingView(rootView: MeetingNotesView(model: model) { [weak self] in
                self?.onStop?()
            })
            let panel = NSPanel(
                contentRect: .zero,
                styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .utilityWindow],
                backing: .buffered,
                defer: false)
            panel.title = "Meeting Notes"
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.becomesKeyOnlyIfNeeded = true
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            panel.delegate = self
            panel.contentView = hosting
            self.panel = panel
        }
        dockRight()
        panel?.orderFront(nil) // don't steal focus from the meeting
    }

    /// Returns the collected notes and resets for the next meeting.
    func closeAndCollect() -> String {
        let text = model.text.trimmingCharacters(in: .whitespacesAndNewlines)
        panel?.orderOut(nil)
        model.text = ""
        return text
    }

    private func dockRight() {
        guard let panel, let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let width: CGFloat = 340
        panel.setFrame(
            NSRect(x: visible.maxX - width, y: visible.minY,
                   width: width, height: visible.height),
            display: true)
    }
}

final class MeetingNotesModel: ObservableObject {
    @Published var text = ""
    @Published var title = ""
}

struct MeetingNotesView: View {
    @ObservedObject var model: MeetingNotesModel
    var onStop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "record.circle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
                Text(model.title)
                    .font(.headline)
                    .lineLimit(2)
                Spacer()
                Button(action: onStop) {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.small)
                .help("Stop recording and transcribe")
            }
            .padding(.top, 10)

            TextEditor(text: $model.text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
                .overlay(alignment: .topLeading) {
                    if model.text.isEmpty {
                        Text("Jot notes during the call…")
                            .foregroundStyle(.secondary)
                            .padding(.top, 16)
                            .padding(.leading, 13)
                            .allowsHitTesting(false)
                    }
                }

            Text("Added to the transcript when the call ends.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
        }
        .padding(.horizontal, 12)
    }
}
