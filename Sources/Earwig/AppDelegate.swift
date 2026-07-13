import AppKit
import Foundation

// @unchecked Sendable: every member is only touched from the main thread
// (AppKit delegate callbacks, main-runloop Timers, and explicit MainActor
// hops in the pipeline) — the annotation just records that contract for the
// Sendable checker.
final class AppDelegate: NSObject, NSApplicationDelegate, @unchecked Sendable {
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
    // Transcriptions run in the background, serialized so concurrent
    // SpeechAnalyzer sessions don't fight over the model. Detection re-arms as
    // soon as a recording is merged, so back-to-back meetings are caught while
    // earlier ones are still transcribing.
    private var activePipelines = 0
    private var pipelineChain: Task<Void, Never> = Task {}

    // Auto-stop: once a meeting app has been seen on the mic during a
    // recording, stop automatically after it has been off the mic this long.
    private var autoStopTimer: Timer?
    private var sawMeetingOnMic = false
    private var sawAnyAppOnMic = false
    private var meetingSilentTicks = 0
    private let autoStopTickSeconds = 5

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
        } else if activePipelines > 0 {
            symbol = "waveform.circle"
            description = "Earwig transcribing"
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
            var title = String(format: "Recording %02d:%02d", secs / 60, secs % 60)
            if activePipelines > 0 { title += " · transcribing previous" }
            statusMenuItem.title = title
            recordMenuItem.title = "Stop Recording & Transcribe"
        } else if activePipelines > 0 {
            statusMenuItem.title = activePipelines == 1
                ? "Transcribing…"
                : "Transcribing \(activePipelines) recordings…"
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
                sawAnyAppOnMic = false
                meetingSilentTicks = 0
                autoStopTimer = Timer.scheduledTimer(
                    withTimeInterval: TimeInterval(autoStopTickSeconds), repeats: true
                ) { [weak self] _ in
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
    /// The call-end signal is per-app microphone attribution: recording stops
    /// once no *meeting app* has held the mic for the configured grace period.
    /// Unrelated mic holders (dictation tools, a stray browser tab) don't keep
    /// a session alive, so back-to-back calls become separate recordings —
    /// while a quick handoff within the grace window (Teams -> WhatsApp) stays
    /// one session. For calls on apps we don't recognise (manual recordings),
    /// it falls back to "any app holds the mic". Earwig itself is excluded.
    private func autoStopTick() {
        guard recorder.isRecording else { return }

        let meetingAppsOnMic = MeetingDetector.meetingAppsUsingMic()
        if !meetingAppsOnMic.isEmpty {
            sawMeetingOnMic = true
            meetingSilentTicks = 0
            // Record every app that joins the session so the note's `source:`
            // reflects rolled-together calls.
            let newApps = meetingAppsOnMic.filter { !currentMeetingApps.contains($0) }
            if !newApps.isEmpty {
                currentMeetingApps.append(contentsOf: newApps)
                Log.info("On the call: \(currentMeetingApps.joined(separator: ", "))")
            }
            return
        }

        if !sawMeetingOnMic {
            // No known meeting app has ever held the mic this session — an
            // unrecognised call app, or a manual recording. Fall back to
            // watching for the mic being released entirely.
            if !MeetingDetector.bundleIDsUsingMic().isEmpty {
                sawAnyAppOnMic = true
                meetingSilentTicks = 0
                return
            }
            guard sawAnyAppOnMic else { return } // pure manual recording — never auto-stop
        }

        meetingSilentTicks += 1
        if meetingSilentTicks * autoStopTickSeconds >= config.effectiveAutoStopGrace {
            let what = sawMeetingOnMic ? "meeting app" : "app"
            Log.info("Call ended — no \(what) on the microphone for \(config.effectiveAutoStopGrace)s; auto-stopping")
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

        Task { @MainActor in
            do {
                _ = try await recorder.stop(mergedTo: audioURL)
            } catch {
                detector.suspended = false
                currentMeetingApps = []
                Log.info("Recording stop failed: \(error)")
                showError("Meeting processing failed", detail: error.localizedDescription)
                updateIcon(); updateStatusLine()
                return
            }

            // Recording is safely on disk — start listening for the next
            // meeting right away; transcription continues in the background.
            detector.suspended = false
            currentMeetingApps = []
            activePipelines += 1
            updateIcon(); updateStatusLine()

            let cfg = config
            pipelineChain = Task { [previous = pipelineChain] in
                await previous.value
                await self.transcribeAndWrite(
                    audioURL: audioURL, startedAt: startedAt, duration: duration,
                    apps: apps, stamp: stamp, config: cfg)
            }
        }
    }

    private func transcribeAndWrite(
        audioURL: URL, startedAt: Date, duration: TimeInterval,
        apps: [String], stamp: String, config cfg: Config
    ) async {
        do {
            let transcript = try await Transcriber.transcribe(
                audioURL: audioURL, localeIdentifier: cfg.localeIdentifier)
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
            Log.info("Note written: \(noteURL.path)")
            await MainActor.run {
                lastNoteURL = noteURL
                lastNoteMenuItem.title = "Last note: \(noteURL.lastPathComponent)"
                lastNoteMenuItem.isHidden = false
                NSSound(named: "Hero")?.play()
            }
        } catch {
            Log.info("Pipeline failed for \(audioURL.lastPathComponent): \(error)")
            await MainActor.run {
                showError("Meeting transcription failed", detail: error.localizedDescription +
                    "\nThe audio is preserved at \(audioURL.path) — re-run with --process.")
            }
        }
        await MainActor.run {
            activePipelines -= 1
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
        if recorder.isRecording || activePipelines > 0 {
            let alert = NSAlert()
            alert.messageText = recorder.isRecording
                ? "Recording in progress"
                : "Transcription in progress"
            alert.informativeText = recorder.isRecording
                ? "Stop recording and quit? The current recording will be discarded."
                : "A recording is still being transcribed. Quit anyway? The audio is saved — re-run it later with --process."
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
