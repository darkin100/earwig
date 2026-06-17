import Foundation

/// A meeting as shown in the browser: parsed from a `meeting-<stamp>.md` note,
/// with a sibling `.transcript.json` referenced when present.
struct Meeting: Identifiable, Hashable {
    let id: String          // stem, e.g. "meeting-2026-06-15-1403"
    let title: String       // source + time, e.g. "Microsoft Teams · 14:03"
    let date: Date
    let durationMinutes: Int
    let source: String
    let speakers: [String]
    let preview: String      // first ~120 chars of spoken transcript text
    let mdURL: URL
    let transcriptURL: URL?  // sibling .transcript.json if present
    let summaryURL: URL?     // sibling .summary.json if present
    let summaryTLDR: String? // the summary's one-line TL;DR, for list previews
    let audioURL: URL?       // recording at <audioFolder>/<stem>.m4a if present
    let hasVoiceprints: Bool // true when a sibling <stem>.speakers.json exists (naming needs it)
}

extension Meeting {
    /// All files that belong to a meeting (note + sidecars + audio), whether or not each exists.
    static func associatedFileURLs(stem: String, notesFolder: URL, audioFolder: URL) -> [URL] {
        [
            notesFolder.appendingPathComponent("\(stem).md"),
            notesFolder.appendingPathComponent("\(stem).transcript.json"),
            notesFolder.appendingPathComponent("\(stem).summary.json"),
            notesFolder.appendingPathComponent("\(stem).speakers.json"),
            notesFolder.appendingPathComponent("\(stem).notes.md"),
            audioFolder.appendingPathComponent("\(stem).m4a"),
        ]
    }
}

extension Meeting {
    static func loadAll(from notesFolder: URL, audioFolder: URL) -> [Meeting] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: notesFolder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return entries.compactMap { url -> Meeting? in
            let name = url.lastPathComponent
            guard name.hasPrefix("meeting-"), name.hasSuffix(".md") else { return nil }
            // The note itself is "<stem>.md"; sidecars like "<stem>.notes.md" / ".transcript.md"
            // have an inner dot, so drop anything but the bare stem.
            guard !name.dropLast(3).contains(".") else { return nil }
            return parse(mdURL: url, notesFolder: notesFolder, audioFolder: audioFolder)
        }
    }

    private static func parse(mdURL: URL, notesFolder: URL, audioFolder: URL) -> Meeting? {
        guard let raw = try? String(contentsOf: mdURL, encoding: .utf8) else { return nil }
        let stem = mdURL.deletingPathExtension().lastPathComponent

        let (frontmatter, body) = splitFrontmatter(raw)
        let source = frontmatter["source"] ?? "Meeting"
        let date = parseDate(frontmatter["date"]) ?? fileDate(stem: stem) ?? Date()
        let durationMinutes = Int(frontmatter["duration_minutes"] ?? "") ?? 0
        let speakers = parseSpeakers(frontmatter["speakers"])
        let preview = firstSpokenLine(in: body)

        let timeLabel = clockLabel(for: date)
        let sourceLabel = source.isEmpty ? "Meeting" : source
        let title = "\(sourceLabel) · \(timeLabel)"

        let transcriptURL = notesFolder.appendingPathComponent("\(stem).transcript.json")
        let hasTranscript = FileManager.default.fileExists(atPath: transcriptURL.path)

        let summaryURL = notesFolder.appendingPathComponent("\(stem).summary.json")
        let hasSummary = FileManager.default.fileExists(atPath: summaryURL.path)
        let summaryTLDR = hasSummary ? (try? SummaryStore.read(from: summaryURL))?.summary.tldr : nil

        let speakersURL = notesFolder.appendingPathComponent("\(stem).speakers.json")
        let hasVoiceprints = FileManager.default.fileExists(atPath: speakersURL.path)

        let audioURL = audioFolder.appendingPathComponent("\(stem).m4a")
        let hasAudio = FileManager.default.fileExists(atPath: audioURL.path)

        return Meeting(
            id: stem,
            title: title,
            date: date,
            durationMinutes: durationMinutes,
            source: sourceLabel,
            speakers: speakers,
            preview: preview,
            mdURL: mdURL,
            transcriptURL: hasTranscript ? transcriptURL : nil,
            summaryURL: hasSummary ? summaryURL : nil,
            summaryTLDR: summaryTLDR,
            audioURL: hasAudio ? audioURL : nil,
            hasVoiceprints: hasVoiceprints
        )
    }

    private static func splitFrontmatter(_ raw: String) -> ([String: String], String) {
        let lines = raw.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            return ([:], raw)
        }
        var fields: [String: String] = [:]
        var bodyStart = lines.count
        for index in 1 ..< lines.count {
            let line = lines[index]
            if line.trimmingCharacters(in: .whitespaces) == "---" {
                bodyStart = index + 1
                break
            }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if !key.isEmpty { fields[key] = value }
        }
        let body = bodyStart < lines.count ? lines[bodyStart...].joined(separator: "\n") : ""
        return (fields, body)
    }

    private static func parseSpeakers(_ value: String?) -> [String] {
        guard var value, !value.isEmpty else { return [] }
        if value.hasPrefix("[") { value.removeFirst() }
        if value.hasSuffix("]") { value.removeLast() }
        return value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        return frontmatterDateFormatter.date(from: value)
    }

    private static func fileDate(stem: String) -> Date? {
        let parts = stem.replacingOccurrences(of: "meeting-", with: "")
        return stemDateFormatter.date(from: parts)
    }

    private static func clockLabel(for date: Date) -> String {
        clockFormatter.string(from: date)
    }

    /// First spoken line after `## Transcript`, skipping turn headers, max 120 chars.
    private static func firstSpokenLine(in body: String) -> String {
        let lines = body.components(separatedBy: "\n")
        var seenTranscriptHeader = false
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line == "## Transcript" {
                seenTranscriptHeader = true
                continue
            }
            guard seenTranscriptHeader else { continue }
            if line.isEmpty { continue }
            if line.hasPrefix("#") { continue }
            if isTurnHeader(line) { continue }
            return truncated(line)
        }
        // No transcript header found — fall back to the first meaningful line.
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || isTurnHeader(line) { continue }
            return truncated(line)
        }
        return ""
    }

    private static func isTurnHeader(_ line: String) -> Bool {
        line.hasPrefix("**") && line.contains("·")
    }

    private static func truncated(_ text: String) -> String {
        if text.count <= 120 { return text }
        let end = text.index(text.startIndex, offsetBy: 120)
        return String(text[..<end]).trimmingCharacters(in: .whitespaces) + "…"
    }

    private static let frontmatterDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    private static let stemDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmm"
        return f
    }()

    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()
}
