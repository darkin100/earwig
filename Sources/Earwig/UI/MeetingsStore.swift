import AppKit
import Foundation
import Observation

/// A day's worth of meetings, newest day first. `Identifiable` so `ForEach` can
/// iterate the groups directly without an explicit `id:` key path.
struct DayGroup: Identifiable {
    let id: Date
    let day: Date
    let meetings: [Meeting]
}

/// Loads and groups the user's meeting notes for the browser window.
@Observable @MainActor
final class MeetingsStore {
    private(set) var meetings: [Meeting] = []
    /// Meetings grouped by calendar day, computed once per `load()` rather than
    /// on every access.
    private(set) var byDay: [DayGroup] = []

    private let notesFolder: URL
    private let audioFolder: URL
    // Set once on the main actor in init; read only in deinit — no concurrent access.
    nonisolated(unsafe) private var observers: [NSObjectProtocol] = []

    init(
        notesFolder: URL = Config.load().notesFolderURL,
        audioFolder: URL = Config.load().audioFolderURL
    ) {
        self.notesFolder = notesFolder
        self.audioFolder = audioFolder
        load()
        // Reload when the background pipeline writes a note, and when the app is
        // reactivated (notes may have changed externally, e.g. a --process run).
        let center = NotificationCenter.default
        for name in [Notification.Name.earwigMeetingsChanged, NSApplication.didBecomeActiveNotification] {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.load() }
            }
            observers.append(token)
        }
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    // Guard against re-assigning identical data — that re-renders mid-click and swallows the tap.
    func load() {
        let loaded = Meeting.loadAll(from: notesFolder, audioFolder: audioFolder)
            .sorted { $0.date > $1.date }
        guard loaded != meetings else { return }
        meetings = loaded
        byDay = group(loaded)
    }

    @discardableResult
    func delete(_ meeting: Meeting) -> Bool {
        let fm = FileManager.default
        var ok = true
        for url in Meeting.associatedFileURLs(
            stem: meeting.id, notesFolder: notesFolder, audioFolder: audioFolder
        ) where fm.fileExists(atPath: url.path) {
            do {
                try fm.removeItem(at: url)
            } catch {
                ok = false
                Log.info("Failed to delete \(url.lastPathComponent): \(error)")
            }
        }
        load()
        return ok
    }

    private func group(_ meetings: [Meeting]) -> [DayGroup] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: meetings) { meeting in
            calendar.startOfDay(for: meeting.date)
        }
        return groups
            .map { DayGroup(id: $0.key, day: $0.key, meetings: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.day > $1.day }
    }
}
