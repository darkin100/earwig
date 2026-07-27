import Foundation

/// A meeting note this voice appears in, and the label it was written under
/// ("Speaker 2" initially; the person's name after a rename).
struct SpeakerAppearance: Codable {
    var noteFile: String
    var label: String
}

/// One voice in the catalogue. `name == nil` means unidentified — the user
/// hasn't listened to the clip and named them yet.
struct SpeakerRecord: Codable, Identifiable {
    let id: UUID
    var name: String?
    var embedding: [Float]
    var clipFile: String
    var context: String // e.g. "Speaker 2 · Q3 Planning Sync"
    var firstHeard: Date
    var lastHeard: Date
    // Optional so records written by older builds still decode.
    var appearances: [SpeakerAppearance]?
}

/// Persistent voice registry: mean speaker embeddings + a sample clip each,
/// stored in Application Support. New meetings match diarized voices against
/// the catalogue so named speakers appear by name in transcripts.
final class SpeakerCatalog {
    static let shared = SpeakerCatalog()

    private let lock = NSLock()
    private var records: [SpeakerRecord]
    private let fileURL: URL
    let clipsDirectory: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Earwig", isDirectory: true)
        fileURL = base.appendingPathComponent("speakers.json")
        clipsDirectory = base.appendingPathComponent("Speakers", isDirectory: true)
        try? FileManager.default.createDirectory(at: clipsDirectory, withIntermediateDirectories: true)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? decoder.decode([SpeakerRecord].self, from: data) {
            records = decoded
        } else {
            records = []
        }
    }

    func all() -> [SpeakerRecord] {
        lock.lock(); defer { lock.unlock() }
        return records
    }

    func clipURL(for record: SpeakerRecord) -> URL {
        clipsDirectory.appendingPathComponent(record.clipFile)
    }

    func setName(id: UUID, name: String) {
        lock.lock(); defer { lock.unlock() }
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        records[index].name = trimmed.isEmpty ? nil : trimmed
        if !trimmed.isEmpty {
            let rewritten = rewriteAppearances(at: index, newLabel: trimmed)
            if rewritten > 0 {
                Log.info("Renamed speaker in \(rewritten) existing meeting note(s)")
            }
        }
        save()
    }

    /// Records that this voice appears in a note under a given label, so a
    /// later rename can update the note retroactively.
    func addAppearance(id: UUID, noteFile: String, label: String) {
        lock.lock(); defer { lock.unlock() }
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        var appearances = records[index].appearances ?? []
        if !appearances.contains(where: { $0.noteFile == noteFile }) {
            appearances.append(SpeakerAppearance(noteFile: noteFile, label: label))
            records[index].appearances = appearances
            save()
        }
    }

    /// Replaces this voice's label in every note it appears in — transcript
    /// turns (`**Speaker 2:**`) and frontmatter keys (`"Speaker 2":`) — and
    /// updates the stored labels so repeat renames keep working.
    private func rewriteAppearances(at index: Int, newLabel: String) -> Int {
        guard var appearances = records[index].appearances, !appearances.isEmpty else { return 0 }
        let notesFolder = Config.load().notesFolderURL
        var rewritten = 0
        for i in appearances.indices {
            let oldLabel = appearances[i].label
            guard oldLabel != newLabel else { continue }
            let noteURL = notesFolder.appendingPathComponent(appearances[i].noteFile)
            guard let content = try? String(contentsOf: noteURL, encoding: .utf8) else { continue }
            let updated = content
                .replacingOccurrences(of: "**\(oldLabel):**", with: "**\(newLabel):**")
                .replacingOccurrences(of: "\"\(oldLabel)\":", with: "\"\(newLabel)\":")
            if updated != content {
                do {
                    try updated.write(to: noteURL, atomically: true, encoding: .utf8)
                    rewritten += 1
                } catch {
                    Log.info("Could not update \(appearances[i].noteFile): \(error)")
                    continue
                }
            }
            appearances[i].label = newLabel
        }
        records[index].appearances = appearances
        return rewritten
    }

    func delete(id: UUID) {
        lock.lock(); defer { lock.unlock() }
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        try? FileManager.default.removeItem(at: clipsDirectory.appendingPathComponent(records[index].clipFile))
        records.remove(at: index)
        save()
    }

    struct Match {
        let id: UUID
        let name: String?
        let similarity: Double
    }

    /// Best cosine match across the catalogue, or nil below the threshold.
    func bestMatch(embedding: [Float], threshold: Double) -> Match? {
        lock.lock(); defer { lock.unlock() }
        var best: (record: SpeakerRecord, similarity: Double)?
        for record in records {
            let similarity = Self.cosineSimilarity(embedding, record.embedding)
            if similarity >= threshold, similarity > (best?.similarity ?? -1) {
                best = (record, similarity)
            }
        }
        guard let best else { return nil }
        return Match(id: best.record.id, name: best.record.name, similarity: best.similarity)
    }

    func touch(id: UUID) {
        lock.lock(); defer { lock.unlock() }
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records[index].lastHeard = Date()
        save()
    }

    /// Adds an unidentified voice: copies its sample clip into the catalogue's
    /// own storage so it survives meeting-audio cleanup. Returns the new
    /// record's id so callers can link note appearances to it.
    @discardableResult
    func register(context: String, embedding: [Float], sampleClip: URL) -> UUID? {
        lock.lock(); defer { lock.unlock() }
        let id = UUID()
        let clipFile = "\(id.uuidString).m4a"
        do {
            try FileManager.default.copyItem(
                at: sampleClip, to: clipsDirectory.appendingPathComponent(clipFile))
        } catch {
            Log.info("Could not store catalogue clip: \(error)")
            return nil
        }
        let now = Date()
        records.append(SpeakerRecord(
            id: id, name: nil, embedding: embedding, clipFile: clipFile,
            context: context, firstHeard: now, lastHeard: now))
        save()
        Log.info("Catalogued new voice (\(context)) — name it via Settings > Speaker Identification")
        return id
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(records) {
            try? data.write(to: fileURL)
        }
    }

    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return -1 }
        var dot: Double = 0, normA: Double = 0, normB: Double = 0
        for i in 0..<a.count {
            dot += Double(a[i]) * Double(b[i])
            normA += Double(a[i]) * Double(a[i])
            normB += Double(b[i]) * Double(b[i])
        }
        guard normA > 0, normB > 0 else { return -1 }
        return dot / ((normA * normB).squareRoot())
    }
}
