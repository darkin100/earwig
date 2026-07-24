import Foundation

/// Builds the markdown transcript file that Earwig writes for each meeting.
/// Deliberately raw: summarisation/action-items are handled downstream
/// (Claude Cowork) — Earwig's job ends at speech-to-text.
enum TranscriptNote {
    static func markdown(
        transcript: String,
        meetingDate: Date,
        duration: TimeInterval,
        apps: [String],
        title: String? = nil,
        windowTitles: [String] = [],
        speakerCount: Int? = nil,
        speakerSamples: [(speaker: String, path: String)] = []
    ) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        let dateString = dateFormatter.string(from: meetingDate)
        let minutes = Int((duration / 60).rounded())
        let heading = title ?? "Meeting \(dateString)"

        var frontmatter = """
        ---
        title: \(yamlQuoted(heading))
        date: \(dateString)
        duration_minutes: \(minutes)
        source: \(apps.isEmpty ? "manual recording" : apps.joined(separator: ", "))
        """
        if let speakerCount {
            frontmatter += "\nspeakers: \(speakerCount)"
        }
        if !speakerSamples.isEmpty {
            frontmatter += "\nspeaker_samples:"
            for sample in speakerSamples {
                frontmatter += "\n  \(yamlQuoted(sample.speaker)): \(yamlQuoted(sample.path))"
            }
        }
        if !windowTitles.isEmpty {
            frontmatter += "\nwindow_titles:"
            for windowTitle in windowTitles {
                frontmatter += "\n  - \(yamlQuoted(windowTitle))"
            }
        }
        frontmatter += """

        generated_by: earwig
        status: raw-transcript
        ---
        """

        return """
        \(frontmatter)

        # \(heading)

        ## Transcript

        \(transcript)
        """
    }

    /// Window titles are arbitrary text — always double-quote and escape for YAML.
    private static func yamlQuoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
        return "\"\(escaped)\""
    }
}
