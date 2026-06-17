import Foundation

/// A single display turn in the transcript detail view.
struct TranscriptTurn: Identifiable, Hashable {
    let id = UUID()
    let speaker: String
    let time: String
    let text: String
    let start: TimeInterval
    let end: TimeInterval
}

/// Resolves a meeting's display turns and a plain-text rendering for copying.
/// Prefers the structured `.transcript.json` sidecar; falls back to parsing the `.md` body.
enum MeetingTranscript {
    /// Display turns for the detail view.
    static func turns(for meeting: Meeting) -> [TranscriptTurn] {
        if let url = meeting.transcriptURL, let record = try? MeetingRecord.read(from: url) {
            return record.turns.map { turn in
                TranscriptTurn(
                    speaker: turn.speaker.displayName,
                    time: TimeFormat.timestamp(turn.start) + " – " + TimeFormat.timestamp(turn.end),
                    text: turn.text.trimmingCharacters(in: .whitespacesAndNewlines),
                    start: turn.start,
                    end: turn.end
                )
            }
        }
        return parseMarkdownTurns(meeting.mdURL)
    }

    /// Summarises a transcript's speakers for the Speakers panel: one `SpeakerInfo` per
    /// distinct speaker, in first-appearance order, each carrying a snippet and a playable
    /// sample taken from that speaker's longest turn.
    static func speakers(from turns: [TranscriptTurn]) -> [SpeakerInfo] {
        var order: [String] = []
        var longestByLabel: [String: TranscriptTurn] = [:]

        for turn in turns {
            if longestByLabel[turn.speaker] == nil {
                order.append(turn.speaker)
                longestByLabel[turn.speaker] = turn
            } else if let current = longestByLabel[turn.speaker],
                      (turn.end - turn.start) > (current.end - current.start) {
                longestByLabel[turn.speaker] = turn
            }
        }

        return order.compactMap { label in
            guard let longest = longestByLabel[label] else { return nil }
            return SpeakerInfo(
                label: label,
                isNamed: isNamedLabel(label),
                snippet: snippet(from: longest.text),
                sampleStart: longest.start,
                sampleEnd: longest.end
            )
        }
    }

    /// A label is "named" unless it's a placeholder like `Speaker 3` or `Others`.
    private static func isNamedLabel(_ label: String) -> Bool {
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        if trimmed == "Others" { return false }
        return trimmed.range(of: "^Speaker \\d+$", options: .regularExpression) == nil
    }

    /// Trims and truncates a turn's text to a short snippet (~90 chars with an ellipsis).
    private static func snippet(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let limit = 90
        if trimmed.count <= limit { return trimmed }
        let end = trimmed.index(trimmed.startIndex, offsetBy: limit)
        return String(trimmed[..<end]).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// Loads the persisted summary for a meeting, or nil if none exists yet.
    static func summary(for meeting: Meeting) -> StoredSummary? {
        guard let url = meeting.summaryURL else { return nil }
        return try? SummaryStore.read(from: url)
    }

    /// Speaker + text per turn, joined — what the Copy button puts on the pasteboard.
    static func plainText(for meeting: Meeting) -> String {
        turns(for: meeting)
            .map { "\($0.speaker): \($0.text)" }
            .joined(separator: "\n\n")
    }

    /// Parses turns from the `## Transcript` body of a note. Each turn is a header line
    /// `**Speaker** · 00:06 – 00:12` followed by one or more text lines, blank-separated.
    private static func parseMarkdownTurns(_ mdURL: URL) -> [TranscriptTurn] {
        guard let raw = try? String(contentsOf: mdURL, encoding: .utf8) else { return [] }
        let body = transcriptBody(raw)
        let lines = body.components(separatedBy: "\n")

        var turns: [TranscriptTurn] = []
        var currentSpeaker: String?
        var currentTime = ""
        var currentText: [String] = []

        func flush() {
            guard let speaker = currentSpeaker else { return }
            let text = currentText.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            let (start, end) = secondsRange(from: currentTime)
            turns.append(TranscriptTurn(
                speaker: speaker, time: currentTime, text: text, start: start, end: end))
            currentSpeaker = nil
            currentTime = ""
            currentText = []
        }

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if let header = parseHeader(line) {
                flush()
                currentSpeaker = header.speaker
                currentTime = header.time
            } else if !line.isEmpty, currentSpeaker != nil {
                currentText.append(line)
            }
        }
        flush()
        return turns
    }

    /// Parses a turn header time like `00:36 – 00:46` into `(start, end)` seconds.
    /// Falls back to `(0, 0)` when either side is missing or unparseable.
    private static func secondsRange(from time: String) -> (TimeInterval, TimeInterval) {
        // The separator is an en dash (–); accept a hyphen too for safety.
        let parts = time
            .replacingOccurrences(of: "-", with: "–")
            .split(separator: "–", maxSplits: 1, omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let start = parts.first.map(secondsFromClock) ?? 0
        let end = parts.count > 1 ? secondsFromClock(parts[1]) : 0
        return (start, end)
    }

    /// Parses an `MM:SS` or `H:MM:SS` clock string into seconds. Returns 0 on failure.
    static func secondsFromClock(_ s: String) -> TimeInterval {
        let fields = s.split(separator: ":").map { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard !fields.isEmpty, fields.allSatisfy({ $0 != nil }) else { return 0 }
        let values = fields.compactMap { $0 }
        switch values.count {
        case 2:
            return TimeInterval(values[0] * 60 + values[1])
        case 3:
            return TimeInterval(values[0] * 3600 + values[1] * 60 + values[2])
        default:
            return 0
        }
    }

    /// Returns the body text following the `## Transcript` header, or the whole note if absent.
    private static func transcriptBody(_ raw: String) -> String {
        guard let range = raw.range(of: "## Transcript") else { return raw }
        return String(raw[range.upperBound...])
    }

    /// Parses a `**Speaker** · 00:06 – 00:12` header into its speaker name and time string.
    private static func parseHeader(_ line: String) -> (speaker: String, time: String)? {
        guard line.hasPrefix("**") else { return nil }
        let afterOpen = line.dropFirst(2)
        guard let closeRange = afterOpen.range(of: "**") else { return nil }
        let speaker = String(afterOpen[..<closeRange.lowerBound])
        var remainder = String(afterOpen[closeRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        if remainder.hasPrefix("·") {
            remainder.removeFirst()
            remainder = remainder.trimmingCharacters(in: .whitespaces)
        }
        return (speaker, remainder)
    }
}
