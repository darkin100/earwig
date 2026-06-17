import Foundation
import Observation

/// Generates missing summaries proactively (launch sweep) and on demand. Tracks per-stem
/// `generating`/`failed` state for UI progress and retry. Routes through `SummaryService`.
@Observable @MainActor
final class SummaryBackfill {
    static let shared = SummaryBackfill()
    private init() {}

    /// Stems currently generating a summary.
    private(set) var generating: Set<String> = []
    /// Stems whose last attempt failed, with the user-facing reason.
    private(set) var failed: [String: String] = [:]
    /// Stems the proactive sweep has already tried this session (so it doesn't loop).
    private var sweepAttempted: Set<String> = []

    private static let minTranscriptChars = 120  // sweep skips trivial transcripts; manual generate still works

    func isGenerating(_ stem: String) -> Bool { generating.contains(stem) }
    func failure(_ stem: String) -> String? { failed[stem] }

    /// Generates a summary if missing. `force` regenerates even when one exists. Non-blocking.
    func ensure(stem: String, notesFolder: URL, config: Config, templateID: String, force: Bool) {
        if generating.contains(stem) { return }
        if !force, summaryExists(stem: stem, notesFolder: notesFolder) { return }
        Task { await generate(stem: stem, notesFolder: notesFolder, config: config, templateID: templateID) }
    }

    /// Sweeps pending stems sequentially (avoids hammering the engine). Skips session-tried stems.
    func sweep(notesFolder: URL, config: Config) {
        guard config.autoSummarize else { return }
        Task {
            for stem in pendingStems(notesFolder: notesFolder) {
                if generating.contains(stem) || sweepAttempted.contains(stem) { continue }
                sweepAttempted.insert(stem)
                await generate(stem: stem, notesFolder: notesFolder, config: config,
                               templateID: config.summaryTemplateID)
            }
        }
    }

    /// Clears session sweep history so a later sweep retries previously-failed stems.
    func resetSweep() { sweepAttempted.removeAll() }

    // MARK: - Internals

    private func generate(stem: String, notesFolder: URL, config: Config, templateID: String) async {
        generating.insert(stem)
        failed[stem] = nil
        var cfg = config
        cfg.summaryTemplateID = templateID
        do {
            _ = try await SummaryService.summarize(
                stem: stem, notesFolder: notesFolder, config: cfg,
                now: Date().timeIntervalSince1970)
            NotificationCenter.default.post(name: .earwigMeetingsChanged, object: nil)
        } catch {
            failed[stem] = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            Log.info("Summary back-fill failed for \(stem): \(failed[stem] ?? "")")
        }
        generating.remove(stem)
    }

    private func summaryExists(stem: String, notesFolder: URL) -> Bool {
        FileManager.default.fileExists(
            atPath: notesFolder.appendingPathComponent("\(stem).summary.json").path)
    }

    private func pendingStems(notesFolder: URL) -> [String] {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: notesFolder, includingPropertiesForKeys: nil)) ?? []
        return files
            .map(\.lastPathComponent)
            .filter { $0.hasSuffix(".transcript.json") }
            .map { String($0.dropLast(".transcript.json".count)) }
            .sorted()
            .filter { stem in
                guard !summaryExists(stem: stem, notesFolder: notesFolder) else { return false }
                let recordURL = notesFolder.appendingPathComponent("\(stem).transcript.json")
                guard let record = try? MeetingRecord.read(from: recordURL), !record.turns.isEmpty else {
                    return false
                }
                return SummaryService.llmText(turns: record.turns).count >= Self.minTranscriptChars
            }
    }
}
