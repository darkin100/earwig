import Foundation

/// Orchestrates summary generation for one stem: transcript → Summarizer → sidecar + note section.
enum SummaryService {
    enum SummaryError: Error, LocalizedError {
        case emptyTranscript
        var errorDescription: String? {
            switch self {
            case .emptyTranscript: return "There's no transcript to summarize yet."
            }
        }
    }

    static func llmText(turns: [TranscriptSegment]) -> String {
        turns.compactMap { turn in
            let text = turn.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return "\(turn.speaker.displayName): \(text)"
        }
        .joined(separator: "\n")
    }

    @discardableResult
    static func summarize(stem: String, notesFolder: URL, config cfg: Config,
                          now: TimeInterval) async throws -> SummaryResult {
        let text = transcriptText(stem: stem, notesFolder: notesFolder)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SummaryError.emptyTranscript
        }
        let engine = SummaryEngineKind.from(cfg.summaryEngine)
        let template = SummaryTemplate.byID(cfg.summaryTemplateID)

        let modelID: String
        let modelName: String
        switch engine {
        case .ollama:
            let model = SummaryModels.resolved(override: cfg.summaryModelID)
            modelID = model.id
            modelName = model.name
        case .apple:
            modelID = ""
            modelName = "Apple Intelligence"
        case .claude:
            modelID = cfg.summaryClaudeModel
            modelName = "Claude (\(cfg.summaryClaudeModel))"
        }

        let notes = NotesStore.read(stem: stem, notesFolder: notesFolder)
        let result = try await Summarizer.shared.summarize(
            transcript: text, template: template, custom: cfg.customSummaryInstructions,
            engine: engine, modelID: modelID, notes: notes)

        try SummaryStore.write(
            result, meeting: stem, model: modelName, templateID: template.id,
            generatedAt: now, to: notesFolder.appendingPathComponent("\(stem).summary.json"))
        appendSummarySection(result, to: notesFolder.appendingPathComponent("\(stem).md"))
        Log.info("Summary written for \(stem) [\(modelName) / \(template.id)]")
        return result
    }

    // MARK: - internals

    private static func transcriptText(stem: String, notesFolder: URL) -> String {
        let recordURL = notesFolder.appendingPathComponent("\(stem).transcript.json")
        if let record = try? MeetingRecord.read(from: recordURL), !record.turns.isEmpty {
            return llmText(turns: record.turns)
        }
        let mdURL = notesFolder.appendingPathComponent("\(stem).md")
        guard let raw = try? String(contentsOf: mdURL, encoding: .utf8) else { return "" }
        return noteBodyText(raw)
    }

    static func noteBodyText(_ raw: String) -> String {
        var lines = raw.components(separatedBy: "\n")
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---" {
            if let close = lines.dropFirst().firstIndex(where: {
                $0.trimmingCharacters(in: .whitespaces) == "---"
            }) {
                lines = Array(lines[(close + 1)...])
            }
        }
        return lines
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in
                !line.isEmpty
                    && !line.hasPrefix("#")
                    && !(line.hasPrefix("**") && line.contains("·"))
            }
            .joined(separator: "\n")
    }

    private static func appendSummarySection(_ result: SummaryResult, to mdURL: URL) {
        guard var note = try? String(contentsOf: mdURL, encoding: .utf8) else { return }
        if let range = note.range(of: "\n## Summary\n") {
            note = String(note[..<range.lowerBound])
        }
        note = note.trimmingCharacters(in: .whitespacesAndNewlines)
            + "\n\n" + markdown(for: result) + "\n"
        try? note.write(to: mdURL, atomically: true, encoding: .utf8)
    }

    static func markdown(for result: SummaryResult) -> String {
        var out = "## Summary\n\n\(result.tldr)\n"
        if !result.keyPoints.isEmpty {
            out += "\n### Key points\n" + result.keyPoints.map { "- \($0)" }.joined(separator: "\n") + "\n"
        }
        if !result.decisions.isEmpty {
            out += "\n### Decisions\n" + result.decisions.map { "- \($0)" }.joined(separator: "\n") + "\n"
        }
        if !result.actionItems.isEmpty {
            out += "\n### Action items\n" + result.actionItems.map { item in
                let prefix = item.owner.map { "**\($0)**: " } ?? ""
                return "- \(prefix)\(item.task)"
            }.joined(separator: "\n") + "\n"
        }
        return out
    }
}
