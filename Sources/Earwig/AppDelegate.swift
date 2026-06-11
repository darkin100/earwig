import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let detector = MeetingDetector()
    private let prompt = RecordPrompt()
    private let recorder = Recorder()
    private var config = Config.load()

    private var currentMeetingApps: [String] = []
    private var statusMenuItem: NSMenuItem!
    private var recordMenuItem: NSMenuItem!
    private var lastNoteMenuItem: NSMenuItem!
    private var elapsedTimer: Timer?
    private var pipelineState: String? // non-nil while transcribing/formatting

    // Auto-stop: once a meeting app has been seen on the mic during a
    // recording, stop automatically after it has been off the mic this long.
    private var autoStopTimer: Timer?
    private var sawMeetingOnMic = false
    private var meetingSilentTicks = 0
    private let autoStopAfterTicks = 9 // 9 ticks x 5s = 45s of "meeting app off mic"

    func applicationDidFinishLaunching(_ notification: Notification) {
        config.ensureFolders()
        setupStatusItem()

        detector.onMeetingDetected = { [weak self] apps in
            self?.meetingDetected(apps: apps)
        }
        detector.start()
        Log.info("Earwig launched. Notes folder: \(config.notesFolder)")
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateIcon()

        let menu = NSMenu()
        statusMenuItem = NSMenuItem(title: "Idle — waiting for meetings", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        lastNoteMenuItem = NSMenuItem(title: "", action: #selector(openLastNote), keyEquivalent: "")
        lastNoteMenuItem.target = self
        lastNoteMenuItem.isHidden = true
        menu.addItem(lastNoteMenuItem)

        menu.addItem(.separator())

        recordMenuItem = NSMenuItem(title: "Start Recording", action: #selector(toggleRecording), keyEquivalent: "r")
        recordMenuItem.target = self
        menu.addItem(recordMenuItem)

        let simulate = NSMenuItem(title: "Simulate Meeting Detection", action: #selector(simulateMeeting), keyEquivalent: "")
        simulate.target = self
        menu.addItem(simulate)

        menu.addItem(.separator())

        let openNotes = NSMenuItem(title: "Open Notes Folder", action: #selector(openNotesFolder), keyEquivalent: "o")
        openNotes.target = self
        menu.addItem(openNotes)

        let openConfig = NSMenuItem(title: "Open Config File", action: #selector(openConfigFile), keyEquivalent: "")
        openConfig.target = self
        menu.addItem(openConfig)

        let openLog = NSMenuItem(title: "Open Log", action: #selector(openLog), keyEquivalent: "")
        openLog.target = self
        menu.addItem(openLog)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Earwig", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        let symbol: String
        let description: String
        if recorder.isRecording {
            symbol = "record.circle.fill"
            description = "Earwig recording"
            button.contentTintColor = .systemRed
        } else if pipelineState != nil {
            symbol = "waveform.circle"
            description = "Earwig processing"
            button.contentTintColor = nil
        } else {
            symbol = "ear"
            description = "Earwig idle"
            button.contentTintColor = nil
        }
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)
    }

    private func updateStatusLine() {
        if recorder.isRecording {
            let secs = Int(recorder.elapsed)
            statusMenuItem.title = String(format: "Recording %02d:%02d", secs / 60, secs % 60)
            recordMenuItem.title = "Stop Recording & Transcribe"
        } else if let state = pipelineState {
            statusMenuItem.title = state
            recordMenuItem.title = "Start Recording"
        } else {
            statusMenuItem.title = "Idle — waiting for meetings"
            recordMenuItem.title = "Start Recording"
        }
    }

    // MARK: Meeting detection

    private func meetingDetected(apps: [String]) {
        guard !recorder.isRecording, !prompt.isVisible else { return }
        currentMeetingApps = apps
        NSSound(named: "Glass")?.play()
        prompt.show(apps: apps) { [weak self] in
            self?.startRecording()
        } onDismiss: {
            Log.info("Prompt dismissed")
        }
    }

    @objc private func simulateMeeting() {
        let apps = detector.runningMeetingApps()
        meetingDetected(apps: apps.isEmpty ? ["Manual test"] : apps)
    }

    // MARK: Recording

    @objc private func toggleRecording() {
        if recorder.isRecording {
            stopRecordingAndProcess()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        detector.suspended = true
        Task { @MainActor in
            do {
                try await recorder.start()
                elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                    self?.updateStatusLine()
                }
                sawMeetingOnMic = false
                meetingSilentTicks = 0
                autoStopTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
                    self?.autoStopTick()
                }
                updateIcon()
                updateStatusLine()
            } catch {
                detector.suspended = false
                Log.info("Failed to start recording: \(error)")
                showError("Could not start recording", detail: error.localizedDescription +
                    "\n\nCheck System Settings > Privacy & Security: Earwig needs Microphone and Screen & System Audio Recording access.")
            }
        }
    }

    /// While recording, watch whether anything is still using the mic.
    /// Calls can roll from one app to another (Teams all-hands -> WhatsApp
    /// follow-up), so the stop signal is "no app at all holds the mic", not
    /// "the meeting app left" — Earwig itself is excluded from the check.
    private func autoStopTick() {
        guard recorder.isRecording else { return }
        let onMic = MeetingDetector.bundleIDsUsingMic()
        if !onMic.isEmpty {
            sawMeetingOnMic = true
            meetingSilentTicks = 0
            return
        }
        guard sawMeetingOnMic else { return } // manual/test recording — never auto-stop
        meetingSilentTicks += 1
        if meetingSilentTicks >= autoStopAfterTicks {
            Log.info("Microphone released by all apps — auto-stopping recording")
            stopRecordingAndProcess()
        }
    }

    private func stopRecordingAndProcess() {
        let apps = currentMeetingApps
        let startedAt = recorder.startedAt ?? Date()
        let duration = recorder.elapsed
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        autoStopTimer?.invalidate()
        autoStopTimer = nil

        let stamp = Self.fileStamp(for: startedAt)
        let audioURL = config.audioFolderURL.appendingPathComponent("meeting-\(stamp).m4a")

        pipelineState = "Finishing recording…"
        updateIcon()
        updateStatusLine()

        Task { @MainActor in
            defer {
                detector.suspended = false
                currentMeetingApps = []
            }
            do {
                _ = try await recorder.stop(mergedTo: audioURL)

                pipelineState = "Transcribing…"
                updateIcon(); updateStatusLine()
                let transcript = try await Transcriber.transcribe(
                    audioURL: audioURL, localeIdentifier: config.localeIdentifier)

                let cfg = config
                let notes = TranscriptNote.markdown(
                    transcript: transcript,
                    meetingDate: startedAt,
                    duration: duration,
                    apps: apps)

                let noteURL = cfg.notesFolderURL.appendingPathComponent("meeting-\(stamp).md")
                try notes.write(to: noteURL, atomically: true, encoding: .utf8)
                if !cfg.keepAudio {
                    try? FileManager.default.removeItem(at: audioURL)
                }
                lastNoteURL = noteURL
                lastNoteMenuItem.title = "Last note: \(noteURL.lastPathComponent)"
                lastNoteMenuItem.isHidden = false
                Log.info("Note written: \(noteURL.path)")
                NSSound(named: "Hero")?.play()
            } catch {
                Log.info("Pipeline failed: \(error)")
                showError("Meeting processing failed", detail: error.localizedDescription +
                    "\nThe audio (if captured) is in \(config.audioFolder).")
            }
            pipelineState = nil
            updateIcon()
            updateStatusLine()
        }
    }

    private var lastNoteURL: URL?

    private static func fileStamp(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmm"
        return f.string(from: date)
    }

    // MARK: Menu actions

    @objc private func openNotesFolder() {
        NSWorkspace.shared.open(config.notesFolderURL)
    }

    @objc private func openConfigFile() {
        NSWorkspace.shared.open(Config.configURL)
    }

    @objc private func openLog() {
        NSWorkspace.shared.open(Log.logURL)
    }

    @objc private func openLastNote() {
        if let lastNoteURL { NSWorkspace.shared.open(lastNoteURL) }
    }

    @objc private func quit() {
        if recorder.isRecording {
            let alert = NSAlert()
            alert.messageText = "Recording in progress"
            alert.informativeText = "Stop recording and quit? The current recording will be discarded."
            alert.addButton(withTitle: "Quit Anyway")
            alert.addButton(withTitle: "Cancel")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() != .alertFirstButtonReturn { return }
        }
        NSApp.terminate(nil)
    }

    private func showError(_ message: String, detail: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = detail
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
