import Foundation

/// Free-text user notes stored as `<stem>.notes.md` beside the other sidecars.
enum NotesStore {
    static func url(stem: String, notesFolder: URL) -> URL {
        notesFolder.appendingPathComponent("\(stem).notes.md")
    }

    static func read(stem: String, notesFolder: URL) -> String {
        let fileURL = url(stem: stem, notesFolder: notesFolder)
        return (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
    }

    /// Persists trimmed text. Deletes the file when empty so unused sidecars don't accumulate.
    static func write(_ text: String, stem: String, notesFolder: URL) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let fileURL = url(stem: stem, notesFolder: notesFolder)
        if trimmed.isEmpty {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
        } else {
            try trimmed.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }
}
