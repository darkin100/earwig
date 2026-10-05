import Foundation

/// Finds merged meeting recordings past the retention age so the user can be
/// offered to move them into the audio folder's `archive/` subfolder. Only
/// `meeting-<yyyy-MM-dd-HHmm>.m4a` files at the top of the audio folder
/// qualify: the per-meeting speaker clips (linked from notes), stashed live
/// notes, already-archived recordings and anything else are never candidates.
enum AudioRetention {
    struct Candidate {
        let url: URL
        let bytes: Int64
    }

    /// The recording's start time, read from its file name — more reliable
    /// than filesystem dates, which copies and restores rewrite.
    static func recordingDate(fileName: String) -> Date? {
        let prefix = "meeting-", suffix = ".m4a"
        guard fileName.hasPrefix(prefix), fileName.hasSuffix(suffix) else { return nil }
        let stamp = fileName.dropFirst(prefix.count).dropLast(suffix.count)
        // "yyyy-MM-dd-HHmm": exactly this shape, so "-livenotes" etc. never match.
        let shape = "dddd-dd-dd-dddd"
        guard stamp.count == shape.count,
              zip(stamp, shape).allSatisfy({ $1 == "d" ? $0.isASCII && $0.isNumber : $0 == $1 })
        else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmm"
        return f.date(from: String(stamp))
    }

    /// Recordings in `folder` older than `days` days, oldest first. `days <= 0`
    /// means keep forever, so nothing is ever expired.
    static func expired(folder: URL, olderThanDays days: Int, now: Date = Date()) -> [Candidate] {
        guard days > 0,
              let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: now),
              let files = try? FileManager.default.contentsOfDirectory(
                  at: folder, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey])
        else { return [] }

        return files.compactMap { url -> (Date, Candidate)? in
            guard let recorded = recordingDate(fileName: url.lastPathComponent),
                  recorded < cutoff,
                  let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true
            else { return nil }
            return (recorded, Candidate(url: url, bytes: Int64(values.fileSize ?? 0)))
        }
        .sorted { $0.0 < $1.0 }
        .map(\.1)
    }

    static let archiveFolderName = "archive"

    static func archiveFolder(in audioFolder: URL) -> URL {
        audioFolder.appendingPathComponent(archiveFolderName, isDirectory: true)
    }

    /// Moves `candidates` into `archiveFolder`, returning the bytes moved. A
    /// recording whose name is already taken in the archive stays where it is
    /// — nothing is ever overwritten or deleted.
    @discardableResult
    static func archive(_ candidates: [Candidate], to archiveFolder: URL) -> Int64 {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: archiveFolder, withIntermediateDirectories: true)
        } catch {
            Log.info("Audio archive: could not create \(archiveFolder.path): \(error)")
            return 0
        }
        var moved: Int64 = 0
        var count = 0
        for candidate in candidates {
            let destination = archiveFolder.appendingPathComponent(candidate.url.lastPathComponent)
            do {
                try fm.moveItem(at: candidate.url, to: destination)
                moved += candidate.bytes
                count += 1
            } catch {
                Log.info("Audio archive could not move \(candidate.url.lastPathComponent): \(error)")
            }
        }
        Log.info("Audio archive: moved \(count) recording(s), \(formatted(bytes: moved)), to \(archiveFolder.path)")
        return moved
    }

    static func formatted(bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// "2 months", "1 year", "45 days" — for the cleanup prompt.
    static func describe(days: Int) -> String {
        if days % 365 == 0 { return days == 365 ? "1 year" : "\(days / 365) years" }
        if days % 30 == 0 { return days == 30 ? "1 month" : "\(days / 30) months" }
        return "\(days) days"
    }
}
