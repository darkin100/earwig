import AppKit
import SwiftUI

/// The Settings… window: a small SwiftUI form over config.json.
/// Changes apply to new recordings; the AppDelegate reloads its config via
/// `onSaved` after every save.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    var onSaved: (() -> Void)?
    private var window: NSWindow?

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = SettingsView(onSaved: { [weak self] in self?.onSaved?() })
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Earwig Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
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

struct SettingsView: View {
    var onSaved: () -> Void

    @State private var notesFolder: String
    @State private var audioFolder: String
    @State private var keepAudio: Bool
    @State private var localeIdentifier: String
    @State private var autoStopGrace: Int
    @State private var whisperModel: String
    @State private var enableDiarization: Bool
    @State private var saved = false

    private static let modelChoices: [(id: String, label: String)] = [
        ("large-v3-v20240930_turbo", "Whisper large-v3 turbo (best, ~1.5 GB)"),
        ("large-v3-v20240930_626MB", "Whisper large-v3 compressed (626 MB)"),
        ("distil-large-v3", "Distil Whisper large-v3 (fastest)"),
        ("apple", "Apple built-in speech model"),
    ]

    init(onSaved: @escaping () -> Void) {
        self.onSaved = onSaved
        let config = Config.load()
        _notesFolder = State(initialValue: config.notesFolder)
        _audioFolder = State(initialValue: config.audioFolder)
        _keepAudio = State(initialValue: config.keepAudio)
        _localeIdentifier = State(initialValue: config.localeIdentifier)
        _autoStopGrace = State(initialValue: config.effectiveAutoStopGrace)
        _whisperModel = State(initialValue: config.effectiveWhisperModel)
        _enableDiarization = State(initialValue: config.effectiveDiarization)
    }

    private var modelChoices: [(id: String, label: String)] {
        var choices = Self.modelChoices
        if !choices.contains(where: { $0.id == whisperModel }) {
            choices.append((whisperModel, whisperModel)) // custom value from config.json
        }
        return choices
    }

    var body: some View {
        Form {
            Section("Folders") {
                folderRow(label: "Notes folder", path: $notesFolder)
                folderRow(label: "Audio folder", path: $audioFolder)
                Toggle("Keep audio after transcription", isOn: $keepAudio)
            }

            Section("Transcription") {
                Picker("Model", selection: $whisperModel) {
                    ForEach(modelChoices, id: \.id) { choice in
                        Text(choice.label).tag(choice.id)
                    }
                }
                TextField("Language / locale", text: $localeIdentifier)
                    .help("BCP-47 identifier, e.g. en_GB or en_US")
                Toggle("Speaker diarization (label Speaker 1, Speaker 2…)", isOn: $enableDiarization)
                    .disabled(whisperModel == "apple")
                if whisperModel == "apple" {
                    Text("Diarization needs the Whisper engine.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Recording") {
                Stepper(value: $autoStopGrace, in: 10...300, step: 5) {
                    Text("Auto-stop after \(autoStopGrace)s off the microphone")
                }
            }

            Section {
                HStack {
                    Button("Save") { save() }
                        .keyboardShortcut(.defaultAction)
                    if saved {
                        Text("Saved — applies to new recordings")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func folderRow(label: String, path: Binding<String>) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text((path.wrappedValue as NSString).abbreviatingWithTildeInPath)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Button("Choose…") {
                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.canCreateDirectories = true
                panel.directoryURL = URL(fileURLWithPath: (path.wrappedValue as NSString).expandingTildeInPath)
                if panel.runModal() == .OK, let url = panel.url {
                    path.wrappedValue = url.path
                }
            }
        }
    }

    private func save() {
        var config = Config.load()
        config.notesFolder = notesFolder
        config.audioFolder = audioFolder
        config.keepAudio = keepAudio
        config.localeIdentifier = localeIdentifier
        config.autoStopGraceSeconds = autoStopGrace
        config.whisperModel = whisperModel
        config.enableDiarization = enableDiarization
        config.save()
        config.ensureFolders()
        Log.info("Settings saved")
        saved = true
        onSaved()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { saved = false }
    }
}
