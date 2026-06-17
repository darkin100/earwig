import AppKit
import SwiftUI

/// Right column: a meeting's header plus tabbed Summary / Transcript / Action Items /
/// Details. The Summary tab generates and shows an on-device LLM summary; the others reuse
/// the transcript turn list and metadata.
struct MeetingDetailView: View {
    let meeting: Meeting?
    let store: MeetingsStore
    let onDelete: () -> Void

    @State private var tab: MeetingTab = .summary
    @State private var confirmingDelete = false
    @State private var turns: [TranscriptTurn] = []
    @State private var speakers: [SpeakerInfo] = []
    @State private var stored: StoredSummary?
    @State private var templateID = SummaryTemplate.defaultID
    @State private var namingSpeaker: SpeakerSelection?
    @State private var showSpeakersPanel = false
    @State private var audio = AudioPlayer.shared
    @State private var isReprocessing = false
    @State private var reprocessError: String?
    @State private var backfill = SummaryBackfill.shared
    @State private var wasGenerating = false
    @State private var notesText = ""
    /// The meeting `notesText` currently belongs to, so autosave/flush always writes to the right
    /// file even as the selection changes. Nil once a meeting is deleted, to prevent resurrecting it.
    @State private var notesStem: String?
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        Group {
            if let meeting {
                detail(meeting)
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
        .task(id: meeting?.id) { load(meeting) }
        .onChange(of: meeting?.id) { audio.stop() }
        // When a back-fill / regenerate finishes, pick up the freshly-written summary and toast.
        .onChange(of: backfill.generating) {
            guard let meeting else { return }
            let now = backfill.isGenerating(meeting.id)
            if wasGenerating && !now {
                stored = loadSummary(meeting)
                if backfill.failure(meeting.id) != nil {
                    ToastCenter.shared.error("Couldn't generate the summary")
                } else if stored != nil {
                    ToastCenter.shared.success("Summary ready")
                }
            }
            wasGenerating = now
        }
        .onDisappear { audio.stop() }
        .onChange(of: notesText) { debouncedSaveNotes() }
        .confirmationDialog(
            "Delete \"\(meeting?.title ?? "")\"?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let meeting else { return }
                // Stop any pending notes save and detach from this stem so the reload that
                // follows (selection → nil) can't rewrite the just-deleted notes file.
                saveTask?.cancel()
                saveTask = nil
                notesStem = nil
                let ok = store.delete(meeting)
                onDelete()
                if ok {
                    ToastCenter.shared.success("Meeting deleted")
                } else {
                    ToastCenter.shared.error("Some files could not be deleted")
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes the note, transcript and recording. This cannot be undone.")
        }
    }

    private func load(_ meeting: Meeting?) {
        // Persist the outgoing meeting's notes (under its own stem) before swapping in the new one.
        flushNotes()
        turns = meeting.map { MeetingTranscript.turns(for: $0) } ?? []
        speakers = MeetingTranscript.speakers(from: turns)
        stored = meeting.flatMap { loadSummary($0) }
        let cfg = Config.load()
        templateID = stored?.templateID ?? cfg.summaryTemplateID
        let notesFolderURL = cfg.notesFolderURL
        notesStem = meeting?.id
        notesText = meeting.map { NotesStore.read(stem: $0.id, notesFolder: notesFolderURL) } ?? ""
        tab = .summary
        // Auto-generate on open when there's no summary yet (and the transcript is worth it),
        // so the user doesn't have to press Generate.
        if let meeting, stored == nil, cfg.autoSummarize, !transcriptIsTrivial {
            backfill.ensure(stem: meeting.id, notesFolder: cfg.notesFolderURL,
                            config: cfg, templateID: cfg.summaryTemplateID, force: false)
        }
    }

    /// True when there's too little spoken text to bother summarising.
    private var transcriptIsTrivial: Bool {
        turns.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines).count < 120
    }

    private var placeholder: some View {
        EmptyMeetingState()
    }

    private func detail(_ meeting: Meeting) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            header(meeting)
            SegmentedControl(
                selection: $tab,
                items: MeetingTab.allCases.map { t in
                    SegmentItem(t, title: t.title, symbol: t.symbol,
                                badge: t == .actionItems ? (stored?.summary.actionItems.count ?? 0) : 0)
                })
            // Dynamic content (summary / transcript / tasks) sits on its own glossy surface.
            GlossyCard(padding: 0) {
                tabContent(meeting)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(Spacing.xl)
    }

    @ViewBuilder
    private func tabContent(_ meeting: Meeting) -> some View {
        switch tab {
        case .summary:
            SummaryView(
                stored: stored,
                isSummarizing: backfill.isGenerating(meeting.id),
                errorMessage: backfill.failure(meeting.id),
                speakerNames: speakers.map(\.label),
                templateID: $templateID,
                onGenerate: { regenerate(meeting) },
                onCopy: copySummary)
        case .transcript:
            transcript(meeting, turns)
        case .notes:
            NotesView(text: $notesText)
        case .actionItems:
            ActionItemsView(stored: stored)
        case .details:
            MeetingDetailsView(
                meeting: meeting, speakerCount: speakers.count, stored: stored,
                isReprocessing: isReprocessing, reprocessError: reprocessError,
                onReprocess: { reprocess(meeting) },
                onCopyTranscript: { copyTranscript(meeting) })
        }
    }

    private func header(_ meeting: Meeting) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(meeting.title)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(metaLine(meeting))
                        .font(.bodyText)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Button {
                    confirmingDelete = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
                .clickableCursor()
                .accessibilityLabel("Delete meeting")
                .help("Delete this meeting permanently")
            }
            if !speakers.isEmpty {
                speakerSummary(meeting)
            }
        }
    }

    // MARK: - Summary actions

    /// Regenerates the summary via the shared back-fill, so progress and failure state match the
    /// automatic path. Flushes notes first so they are on disk when the summary reads them.
    private func regenerate(_ meeting: Meeting) {
        flushNotes()
        let cfg = Config.load()
        backfill.ensure(stem: meeting.id, notesFolder: cfg.notesFolderURL,
                        config: cfg, templateID: templateID, force: true)
    }

    /// Writes the current notes to disk now, under their owning stem, cancelling any pending save.
    private func flushNotes() {
        saveTask?.cancel()
        saveTask = nil
        persistNotes(notesText, stem: notesStem)
    }

    /// Saves notes after a short quiet period so we don't write on every keystroke.
    private func debouncedSaveNotes() {
        let stem = notesStem
        let text = notesText
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(0.6))
            guard !Task.isCancelled else { return }
            persistNotes(text, stem: stem)
        }
    }

    /// Persists notes for `stem`, but never for a meeting whose note no longer exists (e.g. just
    /// deleted), so a late save can't resurrect an orphaned file. Logs rather than failing silently.
    private func persistNotes(_ text: String, stem: String?) {
        guard let stem else { return }
        let notesFolder = Config.load().notesFolderURL
        guard FileManager.default.fileExists(
            atPath: notesFolder.appendingPathComponent("\(stem).md").path) else { return }
        do {
            try NotesStore.write(text, stem: stem, notesFolder: notesFolder)
        } catch {
            Log.info("Failed to save notes for \(stem): \(error)")
        }
    }

    private func copySummary() {
        guard let stored else { return }
        setPasteboard(SummaryService.markdown(for: stored.summary))
        ToastCenter.shared.success("Summary copied")
    }

    /// Reads the sidecar by path so a freshly generated summary is picked up even when the
    /// `meeting` value predates it (its `summaryURL` would still be nil).
    private func loadSummary(_ meeting: Meeting) -> StoredSummary? {
        let url = Config.load().notesFolderURL.appendingPathComponent("\(meeting.id).summary.json")
        return try? SummaryStore.read(from: url)
    }

    // MARK: - Re-transcribe

    private func reprocess(_ meeting: Meeting) {
        guard !isReprocessing else { return }
        isReprocessing = true
        reprocessError = nil
        audio.stop()
        Task {
            do {
                try await MeetingReprocessor.reprocess(meeting, config: Config.load())
                await MainActor.run {
                    NotificationCenter.default.post(name: .earwigMeetingsChanged, object: nil)
                    turns = MeetingTranscript.turns(for: meeting)
                    speakers = MeetingTranscript.speakers(from: turns)
                    isReprocessing = false
                }
            } catch {
                await MainActor.run {
                    reprocessError = error.localizedDescription
                    isReprocessing = false
                }
            }
        }
    }

    private func copyTranscript(_ meeting: Meeting) {
        setPasteboard(MeetingTranscript.plainText(for: meeting))
        ToastCenter.shared.success("Transcript copied")
    }

    private func setPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    // MARK: - Speakers

    private func speakerSummary(_ meeting: Meeting) -> some View {
        SpeakerSummaryChip(speakers: speakers) {
            showSpeakersPanel = true
        }
        .popover(isPresented: $showSpeakersPanel) {
            SpeakersPanel(
                speakers: speakers,
                audioURL: meeting.audioURL,
                canAssign: meeting.hasVoiceprints,
                onAssign: { info in
                    namingSpeaker = SpeakerSelection(
                        label: info.label,
                        audioURL: meeting.audioURL,
                        sampleStart: info.sampleStart,
                        sampleEnd: info.sampleEnd)
                    showSpeakersPanel = false
                })
        }
        .sheet(item: $namingSpeaker) { selection in
            NameSpeakerSheet(
                meetingID: meeting.id,
                speakerLabel: selection.label,
                audioURL: selection.audioURL,
                sampleStart: selection.sampleStart,
                sampleEnd: selection.sampleEnd
            ) {
                turns = MeetingTranscript.turns(for: meeting)
                speakers = MeetingTranscript.speakers(from: turns)
            }
        }
    }

    // MARK: - Transcript

    private func transcript(_ meeting: Meeting, _ turns: [TranscriptTurn]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                if turns.isEmpty {
                    Text("No transcript available for this meeting.")
                        .font(.bodyText)
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    HStack {
                        Spacer()
                        Button("Copy transcript", systemImage: "doc.on.doc") {
                            copyTranscript(meeting)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                    ForEach(turns) { turn in
                        turnView(meeting, turn)
                    }
                }
            }
            .padding(Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func turnView(_ meeting: Meeting, _ turn: TranscriptTurn) -> some View {
        let isPlaying = audio.playingID == turn.id
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.sm) {
                if let audioURL = meeting.audioURL {
                    playButton(turn, audioURL: audioURL, isPlaying: isPlaying)
                }
                Text(turn.speaker)
                    .font(.label).fontWeight(.semibold)
                    .foregroundStyle(Theme.textPrimary)
                if !turn.time.isEmpty {
                    Text(turn.time)
                        .font(.captionText)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            Text(turn.text)
                .font(.bodyText)
                .foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled)
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(isPlaying ? Theme.elevated : Color.clear))
    }

    private func playButton(_ turn: TranscriptTurn, audioURL: URL, isPlaying: Bool) -> some View {
        Button {
            if isPlaying {
                audio.stop()
            } else {
                audio.play(url: audioURL, from: turn.start, to: turn.end, id: turn.id)
            }
        } label: {
            Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                .font(.caption)
                .foregroundStyle(isPlaying ? Theme.accent : Theme.textSecondary)
        }
        .buttonStyle(.plain)
        .clickableCursor()
        .accessibilityLabel("Play \(turn.speaker) \(turn.time)")
    }

    private func metaLine(_ meeting: Meeting) -> String {
        var parts: [String] = [Self.dateFormatter.string(from: meeting.date)]
        if meeting.durationMinutes > 0 {
            parts.append("\(meeting.durationMinutes) min")
        }
        return parts.joined(separator: " · ")
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEEE, MMM d · HH:mm"
        return f
    }()
}
