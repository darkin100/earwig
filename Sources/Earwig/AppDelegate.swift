import AppKit
import Foundation
import SwiftUI

// @unchecked Sendable: all members touched only from the main thread.
final class AppDelegate: NSObject, NSApplicationDelegate, @unchecked Sendable {
    private var mainWindow: NSWindow?
    private let detector = MeetingDetector()
    private let prompt = RecordPrompt()
    private let recorder = Recorder()
    private var config = Config.load()

    private var currentMeetingApps: [String] = []
    // First-run onboarding. Shown instead of the main window until completed.
    private lazy var onboarding = OnboardingWindowController { [weak self] in
        self?.completeOnboarding()
    }
    private var didStartDetector = false
    private var elapsedTimer: Timer?
    // Serialised pipeline: concurrent SpeechAnalyzer sessions fight over the model.
    // Detection re-arms as soon as recording merges, so back-to-back meetings work.
    private var activePipelines = 0
    private var pipelineChain: Task<Void, Never> = Task {}

    // Auto-stop: after a meeting app has been on mic, stop once it's off this long.
    private var autoStopTimer: Timer?
    private var sawMeetingOnMic = false
    private var meetingSilentTicks = 0
    private let autoStopAfterTicks = 9 // 9 ticks x 5s = 45s of "meeting app off mic"

    // Floating recording pill.
    private lazy var recordingHUD = RecordingHUDController(actions: RecordingHUDActions(
        onStop: { [weak self] in self?.toggleRecording() },
        onOpenWindow: { [weak self] in self?.showMainWindow() },
        onOpenNotes: { [weak self] in self?.openNotesFolder() },
        onOpenConfig: { [weak self] in self?.openConfigFile() },
        onOpenLog: { [weak self] in self?.openLog() },
        onQuit: { NSApp.terminate(nil) }
    ))

    func applicationDidFinishLaunching(_ notification: Notification) {
        config.ensureFolders()
        setupMainMenu()

        // SwiftUI Record button routes through the same path as the menu.
        NotificationCenter.default.addObserver(
            forName: .earwigToggleRecording, object: nil, queue: .main
        ) { [weak self] _ in
            self?.toggleRecording()
        }

        // Reload config so Settings edits take effect without a restart.
        NotificationCenter.default.addObserver(
            forName: .earwigConfigChanged, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.config = Config.load()
            self.config.ensureFolders()
            // Engine/model may have changed — retry previously-failed summaries.
            MainActor.assumeIsolated {
                SummaryBackfill.shared.resetSweep()
                SummaryBackfill.shared.sweep(notesFolder: self.config.notesFolderURL, config: self.config)
            }
        }

        // Re-open onboarding on demand (menu / Settings).
        NotificationCenter.default.addObserver(
            forName: .earwigRerunOnboarding, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onboarding.show() }
        }

        detector.onMeetingDetected = { [weak self] apps in
            self?.meetingDetected(apps: apps)
        }

        if config.hasCompletedOnboarding {
            startDetectorOnce()
            showMainWindow()
            MainActor.assumeIsolated {
                SummaryBackfill.shared.sweep(notesFolder: config.notesFolderURL, config: config)
            }
        } else {
            MainActor.assumeIsolated { onboarding.show() }
        }
        Log.info("Earwig launched. Notes folder: \(config.notesFolder)")
    }

    /// Persists the onboarding flag and transitions into the running app. Idempotent.
    private func completeOnboarding() {
        config.hasCompletedOnboarding = true
        config.save()
        startDetectorOnce()
        showMainWindow()
        MainActor.assumeIsolated {
            SummaryBackfill.shared.sweep(notesFolder: config.notesFolderURL, config: config)
        }
    }

    private func startDetectorOnce() {
        guard !didStartDetector else { return }
        didStartDetector = true
        detector.start()
    }

    func showMainWindow() {
        if let window = mainWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: RootView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "Earwig"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        // Title text would overprint the meeting list under the transparent titlebar.
        window.titleVisibility = .hidden
        let toolbar = NSToolbar(identifier: "EarwigToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        // Open filling the usable screen area (below the menu bar) by default.
        if let screen = NSScreen.main {
            window.setFrame(screen.visibleFrame, display: true)
        } else {
            window.setContentSize(NSSize(width: 1480, height: 960))
            window.center()
        }
        mainWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showMainWindow()
        return true
    }

    @objc private func openHelp() {
        showMainWindow()
        NotificationCenter.default.post(name: .earwigOpenHelp, object: nil)
    }

    @objc private func openAbout() {
        showMainWindow()
        NotificationCenter.default.post(name: .earwigOpenAbout, object: nil)
    }

    // MARK: Main menu

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        mainMenu.addItem(appMenuItem())
        mainMenu.addItem(editMenuItem())
        mainMenu.addItem(captureMenuItem())
        mainMenu.addItem(earwigMenuItem())

        let windowMenu = windowMenuItem()
        mainMenu.addItem(windowMenu)

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu.submenu
    }

    private func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        for child in items {
            menu.addItem(child)
        }
        item.submenu = menu
        return item
    }

    /// A nil target routes the action to the first responder (standard Edit commands).
    private func item(
        _ title: String, _ action: Selector?, key: String = "",
        modifiers: NSEvent.ModifierFlags = .command, target: AnyObject? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        if !key.isEmpty {
            item.keyEquivalentModifierMask = modifiers
        }
        item.target = target
        return item
    }

    private func appMenuItem() -> NSMenuItem {
        submenu("Earwig", [
            item("About Earwig", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), target: NSApp),
            .separator(),
            item("Settings…", #selector(openSettings), key: ",", target: self),
            item("Setup…", #selector(rerunOnboarding), target: self),
            .separator(),
            item("Hide Earwig", #selector(NSApplication.hide(_:)), key: "h", target: NSApp),
            item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), key: "h",
                 modifiers: [.command, .option], target: NSApp),
            .separator(),
            item("Quit Earwig", #selector(quit), key: "q", target: self),
        ])
    }

    private func editMenuItem() -> NSMenuItem {
        submenu("Edit", [
            item("Undo", Selector(("undo:")), key: "z"),
            item("Redo", Selector(("redo:")), key: "z", modifiers: [.command, .shift]),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), key: "x"),
            item("Copy", #selector(NSText.copy(_:)), key: "c"),
            item("Paste", #selector(NSText.paste(_:)), key: "v"),
            item("Select All", #selector(NSText.selectAll(_:)), key: "a"),
        ])
    }

    private func captureMenuItem() -> NSMenuItem {
        submenu("Capture", [
            item("Start/Stop Recording", #selector(toggleRecording), key: "r", target: self),
            item("Simulate Meeting Detection", #selector(simulateMeeting), target: self),
        ])
    }

    private func earwigMenuItem() -> NSMenuItem {
        submenu("View", [
            item("Open Earwig Window", #selector(openMainWindow), target: self),
            item("Search...", #selector(openSearch), key: "k", target: self),
            .separator(),
            item("Open Notes Folder", #selector(openNotesFolder), key: "o", target: self),
            item("Open Config File", #selector(openConfigFile), target: self),
            item("Open Log", #selector(openLog), target: self),
        ])
    }

    private func windowMenuItem() -> NSMenuItem {
        submenu("Window", [
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), key: "m"),
            item("Zoom", #selector(NSWindow.performZoom(_:))),
        ])
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

    @objc func toggleRecording() {
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
                RecordingState.shared.phase = .recording
                RecordingState.shared.elapsed = 0
                recordingHUD.show()
                mainWindow?.miniaturize(nil) // keep screen clean while sharing
                elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                    guard let self else { return }
                    MainActor.assumeIsolated {
                        RecordingState.shared.elapsed = self.recorder.elapsed
                    }
                }
                sawMeetingOnMic = false
                meetingSilentTicks = 0
                autoStopTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
                    self?.autoStopTick()
                }
            } catch {
                detector.suspended = false
                Log.info("Failed to start recording: \(error)")
                showError("Could not start recording", detail: error.localizedDescription +
                    "\n\nCheck System Settings > Privacy & Security: Earwig needs Microphone and Screen & System Audio Recording access.")
            }
        }
    }

    /// Checks whether any app (other than Earwig) still holds the mic.
    /// Stops on "mic totally idle" not "meeting app left", so calls can roll between apps.
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

        Task { @MainActor in
            // Switch pill off "recording" immediately — merging takes a few seconds.
            RecordingState.shared.phase = .transcribing
            recordingHUD.show()

            let recording: Recorder.Recording
            do {
                recording = try await recorder.stop(mergedTo: audioURL)
            } catch {
                detector.suspended = false
                currentMeetingApps = []
                Log.info("Recording stop failed: \(error)")
                showError("Meeting processing failed", detail: error.localizedDescription)
                refreshPhase()
                return
            }

            // Recording is on disk — re-arm detection immediately; transcription runs in background.
            detector.suspended = false
            currentMeetingApps = []
            activePipelines += 1
            RecordingState.shared.phase = .transcribing
            recordingHUD.show()

            let cfg = config
            let rec = recording
            pipelineChain = Task { [previous = pipelineChain] in
                await previous.value
                await self.transcribeAndWrite(
                    recording: rec, startedAt: startedAt, duration: duration,
                    apps: apps, stamp: stamp, config: cfg)
            }
        }
    }

    private func transcribeAndWrite(
        recording: Recorder.Recording, startedAt: Date, duration: TimeInterval,
        apps: [String], stamp: String, config cfg: Config
    ) async {
        // Component streams consumed by pipeline; merged m4a kept separately for recovery.
        defer { try? FileManager.default.removeItem(at: recording.workDir) }
        let audioURL = recording.merged
        do {
            cfg.ensureFolders() // folders may have been deleted/moved since launch
            let output = try await DiarizedTranscriber.run(audioURL: audioURL, config: cfg)

            let result = try MeetingWriter.write(
                output, stamp: stamp, meetingDate: startedAt,
                duration: duration, apps: apps, config: cfg)

            if !cfg.keepAudio {
                try? FileManager.default.removeItem(at: audioURL)
            }

            if result.sidecarsComplete {
                Log.info("Note written: \(result.noteURL.path) [\(result.mode.rawValue)]")
            } else {
                Log.info("Note written: \(result.noteURL.path) [\(result.mode.rawValue)] — sidecar write failed (speakers.json: \(result.speakersSidecarFailed ? "FAILED" : "ok"), transcript.json: \(result.transcriptSidecarFailed ? "FAILED" : "ok"))")
            }
            let noteURL = result.noteURL
            let sidecarsComplete = result.sidecarsComplete
            await MainActor.run {
                NotificationCenter.default.post(name: .earwigMeetingsChanged, object: nil)
                if sidecarsComplete {
                    NSSound(named: "Hero")?.play()
                } else {
                    // Speaker data write failed — naming unavailable for this meeting.
                    NSSound(named: "Basso")?.play()
                    showError("Meeting saved, but speaker data could not be written",
                              detail: "The transcript is at \(noteURL.path), but naming speakers will be unavailable for this meeting. See the log for details.")
                }
            }

            // Summary failure must not fail the meeting — transcript is already safe.
            if cfg.autoSummarize {
                await MainActor.run { RecordingState.shared.phase = .summarizing }
                do {
                    _ = try await SummaryService.summarize(
                        stem: "meeting-\(stamp)", notesFolder: cfg.notesFolderURL,
                        config: cfg, now: Date().timeIntervalSince1970)
                    await MainActor.run {
                        NotificationCenter.default.post(name: .earwigMeetingsChanged, object: nil)
                    }
                    Log.info("Auto-summary complete for meeting-\(stamp)")
                } catch {
                    Log.info("Auto-summary failed for meeting-\(stamp): \(error)")
                }
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
            refreshPhase()
        }
    }

    /// Only return to `.idle` when nothing is recording AND no pipeline is running.
    @MainActor
    private func refreshPhase() {
        if recorder.isRecording {
            RecordingState.shared.phase = .recording
            recordingHUD.show()
        } else if activePipelines > 0 {
            RecordingState.shared.phase = .transcribing
            recordingHUD.show()
        } else {
            RecordingState.shared.phase = .idle
            recordingHUD.hide()
        }
    }

    private static func fileStamp(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmm"
        return f.string(from: date)
    }

    // MARK: Menu actions

    @objc private func openMainWindow() {
        showMainWindow()
    }

    @objc private func openSearch() {
        showMainWindow()
        NotificationCenter.default.post(name: .earwigOpenSearch, object: nil)
    }

    @objc private func openSettings() {
        showMainWindow()
    }

    @objc private func rerunOnboarding() {
        MainActor.assumeIsolated { onboarding.show() }
    }

    @objc func openNotesFolder() {
        NSWorkspace.shared.open(config.notesFolderURL)
    }

    @objc func openConfigFile() {
        NSWorkspace.shared.open(Config.configURL)
    }

    @objc func openLog() {
        NSWorkspace.shared.open(Log.logURL)
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

private extension NSToolbarItem.Identifier {
    static let earwigSearch = NSToolbarItem.Identifier("earwig.search")
    static let earwigHelp = NSToolbarItem.Identifier("earwig.help")
    static let earwigAbout = NSToolbarItem.Identifier("earwig.about")
}

extension AppDelegate: NSToolbarDelegate {
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, .earwigSearch, .earwigHelp, .earwigAbout]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, .earwigSearch, .earwigHelp, .earwigAbout]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch identifier {
        case .earwigSearch:
            return toolbarItem(identifier, symbol: "magnifyingglass", label: "Search",
                               action: #selector(openSearch))
        case .earwigHelp:
            return toolbarItem(identifier, symbol: "questionmark.circle", label: "Help",
                               action: #selector(openHelp))
        case .earwigAbout:
            return toolbarItem(identifier, symbol: "info.circle", label: "About",
                               action: #selector(openAbout))
        default:
            return nil
        }
    }

    private func toolbarItem(_ identifier: NSToolbarItem.Identifier, symbol: String, label: String,
                             action: Selector) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.toolTip = label
        item.isBordered = true
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        item.target = self
        item.action = action
        return item
    }
}
