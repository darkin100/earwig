import Foundation

/// Builds the markdown transcript file that Earwig writes for each meeting.
/// Deliberately raw: summarisation/action-items are handled downstream
/// (Claude Cowork) — Earwig's job ends at speech-to-text.
enum TranscriptNote {
    static func markdown(
        transcript: String,
        meetingDate: Date,
        duration: TimeInterval,
        apps: [String]
    ) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        let dateString = dateFormatter.string(from: meetingDate)
        let minutes = Int((duration / 60).rounded())

        return """
        ---
        date: \(dateString)
        duration_minutes: \(minutes)
        source: \(apps.isEmpty ? "manual recording" : apps.joined(separator: ", "))
        generated_by: earwig
        status: raw-transcript
        ---

        # Meeting \(dateString)

        ## Transcript

        \(transcript)
        """
    }
}
