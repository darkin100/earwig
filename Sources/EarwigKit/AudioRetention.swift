import Foundation

/// Finds merged meeting recordings past the retention age so the user can be
/// offered their deletion. Only `meeting-<yyyy-MM-dd-HHmm>.m4a` files qualify:
/// the per-meeting speaker clips (linked from notes), stashed live notes and
/// anything else in the audio folder are never candidates.
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

    /// Permanently deletes `candidates`, returning the bytes actually freed.
    @discardableResult
    static func delete(_ candidates: [Candidate]) -> Int64 {
        var freed: Int64 = 0
        var count = 0
        for candidate in candidates {
            do {
                try FileManager.default.removeItem(at: candidate.url)
                freed += candidate.bytes
                count += 1
            } catch {
                Log.info("Audio cleanup could not delete \(candidate.url.lastPathComponent): \(error)")
            }
        }
        Log.info("Audio cleanup: deleted \(count) recording(s), freed \(formatted(bytes: freed))")
        return freed
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
