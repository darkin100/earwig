import Foundation

/// Re-runs transcription + diarization on saved audio and rewrites the note + sidecars in place.
/// Requires the original audio to still be on disk ("Keep audio" must have been on).
enum MeetingReprocessor {
    enum ReprocessError: Error, LocalizedError {
        case noAudio
        var errorDescription: String? {
            switch self {
            case .noAudio:
                return "The original audio for this meeting is no longer available, so it can't be re-transcribed."
            }
        }
    }

    @discardableResult
    static func reprocess(_ meeting: Meeting, config cfg: Config) async throws -> MeetingWriter.Result {
        guard let audioURL = meeting.audioURL,
              FileManager.default.fileExists(atPath: audioURL.path) else {
            throw ReprocessError.noAudio
        }
        cfg.ensureFolders()
        let output = try await DiarizedTranscriber.run(audioURL: audioURL, config: cfg)
        return try MeetingWriter.write(
            output,
            stamp: stamp(from: meeting.id),
            meetingDate: meeting.date,
            duration: duration(for: meeting),
            // Preserve the original source: "manual recording" → no apps; else the app list.
            apps: meeting.source == "manual recording" ? [] : [meeting.source],
            config: cfg)
    }

    private static func stamp(from stem: String) -> String {
        stem.hasPrefix("meeting-") ? String(stem.dropFirst("meeting-".count)) : stem
    }

    /// Prefers the exact duration from transcript.json; falls back to the note's whole-minute value.
    private static func duration(for meeting: Meeting) -> TimeInterval {
        if let url = meeting.transcriptURL, let record = try? MeetingRecord.read(from: url) {
            return record.durationSeconds
        }
        return TimeInterval(meeting.durationMinutes * 60)
    }
}
