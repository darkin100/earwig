import Foundation
import Observation

// MARK: - Models

struct SearchDoc: Equatable, Identifiable, Sendable {
    let meetingId: String
    let title: String
    let date: Date
    let speakers: [String]
    let transcript: String
    let summary: String

    // TF dictionaries precomputed at init, keyed by lowercase token.
    let titleTokens: [String: Int]
    let summaryTokens: [String: Int]
    let transcriptTokens: [String: Int]

    var id: String { meetingId }

    init(
        meetingId: String,
        title: String,
        date: Date,
        speakers: [String],
        transcript: String,
        summary: String
    ) {
        self.meetingId = meetingId
        self.title = title
        self.date = date
        self.speakers = speakers
        self.transcript = transcript
        self.summary = summary
        self.titleTokens = SearchService.termFrequency(SearchService.tokens(title))
        self.summaryTokens = SearchService.termFrequency(SearchService.tokens(summary))
        self.transcriptTokens = SearchService.termFrequency(SearchService.tokens(transcript))
    }
}

struct SearchHit: Identifiable, Equatable {
    let meetingId: String
    let title: String
    let date: Date
    let snippet: String
    let score: Int

    var id: String { meetingId }
}

// MARK: - Service

/// In-memory keyword search index over stored meetings.
@Observable @MainActor
final class SearchService {
    private(set) var docs: [SearchDoc] = []

    func reload(notesFolder: URL) async {
        let builtDocs = await Task.detached(priority: .userInitiated) {
            SearchService.buildDocs(notesFolder: notesFolder)
        }.value
        docs = builtDocs
    }

    private nonisolated static func buildDocs(notesFolder: URL) -> [SearchDoc] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: notesFolder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let stems = entries
            .map(\.lastPathComponent)
            .filter { $0.hasSuffix(".transcript.json") }
            .map { String($0.dropLast(".transcript.json".count)) }
            .sorted()

        return stems.compactMap { stem -> SearchDoc? in
            let transcriptURL = notesFolder.appendingPathComponent("\(stem).transcript.json")
            guard let record = try? MeetingRecord.read(from: transcriptURL),
                  !record.turns.isEmpty else { return nil }

            let transcript = SummaryService.llmText(turns: record.turns)

            let summaryURL = notesFolder.appendingPathComponent("\(stem).summary.json")
            let stored = try? SummaryStore.read(from: summaryURL)
            let summary: String
            if let s = stored?.summary {
                let parts = ([s.tldr] + s.keyPoints + s.decisions).filter { !$0.isEmpty }
                summary = parts.joined(separator: " ")
            } else {
                summary = ""
            }

            let (title, date) = SearchService.titleAndDate(
                stem: stem, notesFolder: notesFolder, recordDate: record.date)

            let speakers = record.turns
                .map { $0.speaker.displayName }
                .filter { !$0.isEmpty }
                .uniqued()

            return SearchDoc(
                meetingId: stem,
                title: title,
                date: date,
                speakers: speakers,
                transcript: transcript,
                summary: summary
            )
        }
    }

    // MARK: - Ask context

    /// Top-scoring docs for `query` up to `budgetChars`. Top match always included even if it exceeds budget.
    func contextDocs(for query: String, budgetChars: Int) -> [SearchDoc] {
        let hits = SearchService.rank(query: query, in: docs)
        guard !hits.isEmpty else { return [] }

        // Map each hit back to its full SearchDoc (hits carry only the display fields).
        let docsByID = Dictionary(uniqueKeysWithValues: docs.map { ($0.meetingId, $0) })

        var result: [SearchDoc] = []
        var accumulated = 0

        for hit in hits {
            guard let doc = docsByID[hit.meetingId] else { continue }
            let docSize = doc.summary.count + doc.transcript.count
            if result.isEmpty || accumulated + docSize <= budgetChars {
                result.append(doc)
                accumulated += docSize
            } else {
                break
            }
        }
        return result
    }

    // MARK: - Pure static helpers (nonisolated so tests can call without MainActor)

    /// Field-weighted TF score: title×5, summary×3, transcript×1. Sorted by score then date.
    nonisolated static func rank(query: String, in docs: [SearchDoc]) -> [SearchHit] {
        let terms = tokens(query)
        guard !terms.isEmpty else { return [] }

        let scored: [(doc: SearchDoc, score: Int)] = docs.compactMap { doc in
            var score = 0
            for term in terms {
                score += (doc.titleTokens[term] ?? 0) * 5
                score += (doc.summaryTokens[term] ?? 0) * 3
                score += (doc.transcriptTokens[term] ?? 0) * 1
            }
            guard score > 0 else { return nil }
            return (doc, score)
        }

        return scored
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.doc.date > $1.doc.date
            }
            .map { pair in
                SearchHit(
                    meetingId: pair.doc.meetingId,
                    title: pair.doc.title,
                    date: pair.doc.date,
                    snippet: snippet(for: terms, in: pair.doc),
                    score: pair.score
                )
            }
    }

    nonisolated static func tokens(_ text: String) -> [String] {
        let lowered = text.lowercased()
        let cleaned = String(lowered.map { ch -> Character in
            ch.isLetter || ch.isNumber ? ch : " "
        })
        return cleaned.split(separator: " ").compactMap { token -> String? in
            let s = String(token)
            return s.count >= 2 ? s : nil
        }
    }

    nonisolated static func termFrequency(_ tokens: [String]) -> [String: Int] {
        tokens.reduce(into: [:]) { counts, token in
            counts[token, default: 0] += 1
        }
    }

    /// ~160-char window around first match in summary (preferred) or transcript.
    nonisolated static func snippet(for terms: [String], in doc: SearchDoc) -> String {
        let candidates = [doc.summary, doc.transcript].filter { !$0.isEmpty }
        for source in candidates {
            if let window = snippetWindow(for: terms, in: source) {
                return window
            }
        }
        // Fall back: first 160 chars of the best available source.
        let fallback = candidates.first ?? ""
        if fallback.isEmpty { return "" }
        let count = fallback.count
        let end = fallback.index(fallback.startIndex, offsetBy: min(160, count))
        let text = String(fallback[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        return count > 160 ? text + "…" : text
    }

    // MARK: - Private pure helpers

    private nonisolated static func snippetWindow(for terms: [String], in source: String) -> String? {
        let lower = source.lowercased()
        var hitOffset: String.Index? = nil
        for term in terms {
            if let range = lower.range(of: term) {
                if hitOffset == nil || range.lowerBound < hitOffset! {
                    hitOffset = range.lowerBound
                }
            }
        }
        guard let hit = hitOffset else { return nil }

        let windowSize = 160
        let totalChars = source.count
        let hitInt = source.distance(from: source.startIndex, to: hit)
        let halfWindow = windowSize / 2
        let windowStart = max(0, hitInt - halfWindow)
        let windowEnd = min(totalChars, windowStart + windowSize)

        let startIndex = source.index(source.startIndex, offsetBy: windowStart)
        let endIndex = source.index(source.startIndex, offsetBy: windowEnd)
        var window = String(source[startIndex..<endIndex])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if windowStart > 0 { window = "…" + window }
        if windowEnd < totalChars { window = window + "…" }
        return window
    }

    private nonisolated static func titleAndDate(
        stem: String, notesFolder: URL, recordDate: TimeInterval
    ) -> (String, Date) {
        let mdURL = notesFolder.appendingPathComponent("\(stem).md")
        if let raw = try? String(contentsOf: mdURL, encoding: .utf8) {
            let (fm, _) = SearchService.splitFrontmatter(raw)
            let source = fm["source"] ?? "Meeting"
            let date = SearchService.frontmatterDate(fm["date"])
                ?? SearchService.stemDate(stem)
                ?? Date(timeIntervalSince1970: recordDate)
            let title = "\(source.isEmpty ? "Meeting" : source) · \(SearchService.clockLabel(date))"
            return (title, date)
        }
        let date = SearchService.stemDate(stem) ?? Date(timeIntervalSince1970: recordDate)
        return ("Meeting · \(SearchService.clockLabel(date))", date)
    }

    private nonisolated static func splitFrontmatter(_ raw: String) -> ([String: String], String) {
        let lines = raw.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return ([:], raw) }
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

    private nonisolated static func frontmatterDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: value)
    }

    private nonisolated static func stemDate(_ stem: String) -> Date? {
        let parts = stem.replacingOccurrences(of: "meeting-", with: "")
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmm"
        return f.date(from: parts)
    }

    private nonisolated static func clockLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}

// MARK: - Sequence helper

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
