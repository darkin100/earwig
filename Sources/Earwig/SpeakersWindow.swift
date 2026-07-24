import AppKit
import AVFoundation
import SwiftUI

/// Settings > Speaker Identification: listen to catalogued voice clips, name
/// the ones you recognise, delete the ones you don't. Named voices are matched
/// in future meetings so transcripts show real names.
final class SpeakersWindowController: NSObject, NSWindowDelegate {
    static let shared = SpeakersWindowController()
    private var window: NSWindow?

    func show() {
        if let window {
            (window.contentViewController as? NSHostingController<SpeakersView>)?
                .rootView = SpeakersView()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: SpeakersView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "Speaker Identification"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 560, height: 420))
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

struct SpeakersView: View {
    @State private var records: [SpeakerRecord] = []
    @State private var draftNames: [UUID: String] = [:]
    @State private var player: AVAudioPlayer?
    @State private var playingID: UUID?

    private var unidentified: [SpeakerRecord] { records.filter { ($0.name ?? "").isEmpty } }
    private var known: [SpeakerRecord] { records.filter { !($0.name ?? "").isEmpty } }

    var body: some View {
        Group {
            if records.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "person.2.wave.2")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No voices catalogued yet")
                        .font(.headline)
                    Text("After each diarized meeting, unfamiliar voices appear here with a sample clip. Listen, then name the ones you recognise — future transcripts will use their names.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 380)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if !unidentified.isEmpty {
                        Section("Unidentified — listen, then name or delete") {
                            ForEach(unidentified) { row($0) }
                        }
                    }
                    if !known.isEmpty {
                        Section("Known speakers") {
                            ForEach(known) { row($0) }
                        }
                    }
                }
            }
        }
        .frame(minWidth: 540, minHeight: 380)
        .onAppear(perform: reload)
        .onDisappear { stopPlayback() }
    }

    private func row(_ record: SpeakerRecord) -> some View {
        HStack(spacing: 12) {
            Button {
                togglePlayback(record)
            } label: {
                Image(systemName: playingID == record.id ? "stop.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.plain)
            .help(playingID == record.id ? "Stop" : "Play voice sample")

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    TextField("Add name…", text: draftBinding(record))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                        .onSubmit { commitName(record) }
                    if (draftNames[record.id] ?? record.name ?? "") != (record.name ?? "") {
                        Button("Save") { commitName(record) }
                            .controlSize(.small)
                    }
                }
                Text("\(record.context) · last heard \(record.lastHeard.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(role: .destructive) {
                if playingID == record.id { stopPlayback() }
                SpeakerCatalog.shared.delete(id: record.id)
                reload()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Remove this voice and its clip")
        }
        .padding(.vertical, 4)
    }

    private func draftBinding(_ record: SpeakerRecord) -> Binding<String> {
        Binding(
            get: { draftNames[record.id] ?? record.name ?? "" },
            set: { draftNames[record.id] = $0 }
        )
    }

    private func commitName(_ record: SpeakerRecord) {
        guard let draft = draftNames[record.id] else { return }
        SpeakerCatalog.shared.setName(id: record.id, name: draft)
        draftNames[record.id] = nil
        reload()
    }

    private func togglePlayback(_ record: SpeakerRecord) {
        if playingID == record.id {
            stopPlayback()
            return
        }
        stopPlayback()
        let url = SpeakerCatalog.shared.clipURL(for: record)
        do {
            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.play()
            player = newPlayer
            playingID = record.id
        } catch {
            Log.info("Could not play sample clip: \(error)")
        }
    }

    private func stopPlayback() {
        player?.stop()
        player = nil
        playingID = nil
    }

    private func reload() {
        records = SpeakerCatalog.shared.all()
            .sorted { $0.lastHeard > $1.lastHeard }
    }
}
