import Foundation

/// Renders and persists a finished meeting (note + sidecars). Note failure throws;
/// sidecar failures are reported in `Result` so the caller can warn instead of silently claiming success.
enum MeetingWriter {
    struct Result {
        let noteURL: URL
        let mode: DiarizationMode
        let speakersSidecarFailed: Bool
        let transcriptSidecarFailed: Bool

        var sidecarsComplete: Bool { !speakersSidecarFailed && !transcriptSidecarFailed }
    }

    static func write(_ output: DiarizedTranscriber.Output, stamp: String,
                      meetingDate: Date, duration: TimeInterval, apps: [String],
                      config cfg: Config) throws -> Result {
        let meeting = "meeting-\(stamp)"
        let notesFolder = cfg.notesFolderURL
        let noteURL = notesFolder.appendingPathComponent("\(meeting).md")

        let notes: String
        let turns: [TranscriptSegment]
        let profiles: [SpeakerProfile]
        switch output {
        case .plain(let text):
            turns = []
            profiles = []
            notes = TranscriptNote.markdown(
                transcript: text, meetingDate: meetingDate, duration: duration, apps: apps)
        case .diarized(let diarizedTurns, let speakers, let diarizedProfiles):
            turns = diarizedTurns
            profiles = diarizedProfiles
            notes = TranscriptNote.markdown(
                turns: diarizedTurns, speakers: speakers, mode: output.mode,
                meetingDate: meetingDate, duration: duration, apps: apps)
        }

        try notes.write(to: noteURL, atomically: true, encoding: .utf8)

        var speakersSidecarFailed = false
        if cfg.keepSpeakerEmbeddings, !profiles.isEmpty {
            let speakersURL = notesFolder.appendingPathComponent("\(meeting).speakers.json")
            do {
                try SpeakerStore.write(profiles, meeting: meeting, to: speakersURL)
            } catch {
                speakersSidecarFailed = true
                Log.info("speakers.json write failed for \(meeting): \(error)")
            }
        }

        var transcriptSidecarFailed = false
        if case .diarized = output {
            let recordURL = notesFolder.appendingPathComponent("\(meeting).transcript.json")
            let record = MeetingRecord(
                meeting: meeting,
                date: meetingDate.timeIntervalSince1970,
                durationSeconds: duration,
                source: apps.isEmpty ? "manual recording" : apps.joined(separator: ", "),
                mode: output.mode,
                turns: turns)
            do {
                try record.write(to: recordURL)
            } catch {
                transcriptSidecarFailed = true
                Log.info("transcript.json write failed for \(meeting): \(error)")
            }
        }

        return Result(
            noteURL: noteURL, mode: output.mode,
            speakersSidecarFailed: speakersSidecarFailed,
            transcriptSidecarFailed: transcriptSidecarFailed)
    }
}
