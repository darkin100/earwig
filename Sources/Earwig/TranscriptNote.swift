import Foundation

/// Builds the markdown transcript file. Earwig writes raw speech-to-text only.
enum TranscriptNote {
    private static func dateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: date)
    }

    // SpeechAnalyzer token segments include surrounding spaces, causing double spaces after merge.
    private static func normalizeWhitespace(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private static func sourceLine(_ apps: [String]) -> String {
        apps.isEmpty ? "manual recording" : apps.joined(separator: ", ")
    }

    static func markdown(
        transcript: String,
        meetingDate: Date,
        duration: TimeInterval,
        apps: [String]
    ) -> String {
        let ds = dateString(meetingDate)
        let minutes = Int((duration / 60).rounded())
        return """
        ---
        date: \(ds)
        duration_minutes: \(minutes)
        source: \(sourceLine(apps))
        generated_by: earwig
        status: raw-transcript
        diarization: none
        ---

        # Meeting \(ds)

        ## Transcript

        \(transcript)
        """
    }

    static func markdown(
        turns: [TranscriptSegment],
        speakers: [SpeakerLabel],
        mode: DiarizationMode,
        meetingDate: Date,
        duration: TimeInterval,
        apps: [String]
    ) -> String {
        let ds = dateString(meetingDate)
        let minutes = Int((duration / 60).rounded())
        let speakerList = speakers.map(\.displayName).joined(separator: ", ")
        let body = turns.map { turn in
            "**\(turn.speaker.displayName)** · \(TimeFormat.timestamp(turn.start)) – \(TimeFormat.timestamp(turn.end))\n\(normalizeWhitespace(turn.text))"
        }.joined(separator: "\n\n")

        return """
        ---
        date: \(ds)
        duration_minutes: \(minutes)
        source: \(sourceLine(apps))
        generated_by: earwig
        status: raw-transcript
        diarization: \(mode.rawValue)
        speakers: [\(speakerList)]
        ---

        # Meeting \(ds)

        ## Transcript

        \(body)
        """
    }
}
