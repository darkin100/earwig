import AppKit
import Foundation

// @unchecked Sendable: every member is only touched from the main thread
// (AppKit delegate callbacks, main-runloop Timers, and explicit MainActor
// hops in the pipeline) — the annotation just records that contract for the
// Sendable checker.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, @unchecked Sendable {
    func menuWillOpen(_ menu: NSMenu) {
        windowAccessMenuItem?.isHidden = WindowMonitor.isTrusted
        updateStatusLine()
    }

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

    // Window-title tracking (Accessibility permission). Call windows seen
    // during the session provide the meeting title and a fast end-of-call
    // signal when they close.
    private var sessionWindowTitles: Set<String> = []
    private var sessionMeetingTitle: String?
    private var windowAccessMenuItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        config.ensureFolders()
        setupStatusItem()

        detector.onMeetingDetected = { [weak self] apps in
            self?.meetingDetected(apps: apps)
        }
        detector.start()
        if !WindowMonitor.isTrusted {
            Log.info("Accessibility not granted — meeting titles and window-close detection disabled")
            WindowMonitor.requestTrust()
        }
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

        windowAccessMenuItem = NSMenuItem(
            title: "Enable Meeting Titles (Accessibility)…",
            action: #selector(requestWindowAccess), keyEquivalent: "")
        windowAccessMenuItem.target = self
        windowAccessMenuItem.isHidden = WindowMonitor.isTrusted
        menu.addItem(windowAccessMenuItem)

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

        menu.delegate = self
        statusItem.menu = menu
    }

    @objc private func requestWindowAccess() {
        WindowMonitor.requestTrust()
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
                sessionWindowTitles = []
                sessionMeetingTitle = nil
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

    /// Two call-end signals, used together:
    ///  - Microphone attribution: no *meeting app* has held the mic for the
    ///    configured grace period. Unrelated mic holders (dictation tools, a
    ///    stray browser tab) don't keep a session alive, so back-to-back calls
    ///    become separate recordings — while a quick handoff within the grace
    ///    window (Teams -> WhatsApp) stays one session.
    ///  - Window close (needs Accessibility): the call windows seen during the
    ///    session have all closed. This confirms the meeting really ended, so
    ///    the stop happens after a short 10s confirmation instead of the full
    ///    grace period.
    /// For calls on apps we don't recognise (manual recordings), it falls back
    /// to "any app holds the mic". Earwig itself is excluded everywhere.
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
            // Capture call-window titles while the call is live: the meeting
            // title for the note, and trackers for the window-close signal.
            let callWindows = WindowMonitor.callWindowCandidates()
            for window in callWindows where !sessionWindowTitles.contains(window.title) {
                sessionWindowTitles.insert(window.title)
                Log.info("Call window: \(window.app) — \(window.title)")
            }
            if sessionMeetingTitle == nil {
                let onMicWindow = callWindows.first { meetingAppsOnMic.contains($0.app) }
                sessionMeetingTitle = (onMicWindow ?? callWindows.first)?.title
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

        // If every call window we tracked has closed, the meeting is
        // definitively over — stop after a short confirmation instead of
        // waiting out the full grace period.
        var grace = config.effectiveAutoStopGrace
        if !sessionWindowTitles.isEmpty, WindowMonitor.isTrusted {
            let openTitles = Set(WindowMonitor.callWindowCandidates().map(\.title))
            if openTitles.isDisjoint(with: sessionWindowTitles) {
                grace = min(10, grace)
            }
        }

        if meetingSilentTicks * autoStopTickSeconds >= grace {
            let reason = grace < config.effectiveAutoStopGrace
                ? "call windows closed and mic released"
                : "no \(sawMeetingOnMic ? "meeting app" : "app") on the microphone for \(grace)s"
            Log.info("Call ended — \(reason); auto-stopping")
            stopRecordingAndProcess()
        }
    }

    private func stopRecordingAndProcess() {
        let apps = currentMeetingApps
        let meetingTitle = sessionMeetingTitle
        let windowTitles = sessionWindowTitles.sorted()
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
                    apps: apps, meetingTitle: meetingTitle, windowTitles: windowTitles,
                    stamp: stamp, config: cfg)
            }
        }
    }

    private func transcribeAndWrite(
        audioURL: URL, startedAt: Date, duration: TimeInterval,
        apps: [String], meetingTitle: String?, windowTitles: [String],
        stamp: String, config cfg: Config
    ) async {
        do {
            let result = try await Transcriber.transcribe(
                audioURL: audioURL, localeIdentifier: cfg.localeIdentifier,
                whisperModel: cfg.effectiveWhisperModel,
                diarize: cfg.effectiveDiarization)
            let notes = TranscriptNote.markdown(
                transcript: result.text,
                meetingDate: startedAt,
                duration: duration,
                apps: apps,
                title: meetingTitle,
                windowTitles: windowTitles,
                speakerCount: result.speakerCount)
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
