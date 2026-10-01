import Foundation
import Testing

@testable import EarwigKit

/// Audio cleanup: only merged recordings past the retention age are offered
/// for deletion, and nothing is removed until `delete` is called.
struct AudioRetentionTests {
    private func makeFolder(_ names: [String], dirs: [String] = []) throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("earwig-retention-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in names {
            try Data("x".utf8).write(to: folder.appendingPathComponent(name))
        }
        for dir in dirs {
            try FileManager.default.createDirectory(
                at: folder.appendingPathComponent(dir, isDirectory: true), withIntermediateDirectories: true)
        }
        return folder
    }

    private func date(_ stamp: String) -> Date {
        AudioRetention.recordingDate(fileName: "meeting-\(stamp).m4a")!
    }

    @Test func readsDateOnlyFromRecordingNames() {
        #expect(AudioRetention.recordingDate(fileName: "meeting-2026-06-10-0832.m4a") != nil)
        #expect(AudioRetention.recordingDate(fileName: "meeting-2026-06-10-0832-livenotes.txt") == nil)
        #expect(AudioRetention.recordingDate(fileName: "meeting-2026-06-10-0832-speakers") == nil)
        #expect(AudioRetention.recordingDate(fileName: "meeting-2026-06-10-0832.m4a.bak") == nil)
        #expect(AudioRetention.recordingDate(fileName: "notes-2026-06-10-0832.m4a") == nil)
    }

    @Test func offersOnlyRecordingsPastTheCutoffOldestFirst() throws {
        let folder = try makeFolder([
            "meeting-2026-07-29-1000.m4a",           // 60 days + 1h old: expired
            "meeting-2026-06-01-0900.m4a",           // old: expired
            "meeting-2026-08-15-0900.m4a",           // recent: kept
            "meeting-2026-06-01-0900-livenotes.txt", // user notes: kept
            "evals.m4a",                             // unrelated: kept
        ], dirs: ["meeting-2026-06-01-0900-speakers"])
        defer { try? FileManager.default.removeItem(at: folder) }

        let expired = AudioRetention.expired(
            folder: folder, olderThanDays: 60, now: date("2026-09-27-1100"))

        #expect(expired.map(\.url.lastPathComponent) ==
            ["meeting-2026-06-01-0900.m4a", "meeting-2026-07-29-1000.m4a"])
        #expect(expired.allSatisfy { $0.bytes == 1 })
    }

    @Test func findingCandidatesDeletesNothing() throws {
        let folder = try makeFolder(["meeting-2020-01-01-0900.m4a", "meeting-2020-01-02-0900.m4a"])
        defer { try? FileManager.default.removeItem(at: folder) }

        let expired = AudioRetention.expired(folder: folder, olderThanDays: 60)
        #expect(expired.count == 2)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).count == 2)

        let freed = AudioRetention.delete(Array(expired.prefix(1)))
        #expect(freed == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) ==
            ["meeting-2020-01-02-0900.m4a"])
    }

    @Test func zeroDaysNeverExpires() throws {
        let folder = try makeFolder(["meeting-2020-01-01-0900.m4a"])
        defer { try? FileManager.default.removeItem(at: folder) }

        #expect(AudioRetention.expired(folder: folder, olderThanDays: 0).isEmpty)
    }

    @Test func describesRetentionPeriods() {
        #expect(AudioRetention.describe(days: 30) == "1 month")
        #expect(AudioRetention.describe(days: 60) == "2 months")
        #expect(AudioRetention.describe(days: 365) == "1 year")
        #expect(AudioRetention.describe(days: 45) == "45 days")
    }
}
