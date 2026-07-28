import Foundation
import Testing

@testable import EarwigKit

/// The markdown note contract consumed by downstream tooling.
struct NoteFormatTests {
    private let date = Date(timeIntervalSince1970: 1_785_000_000)

    @Test func frontmatterCarriesCoreContract() {
        let note = TranscriptNote.markdown(
            transcript: "**Glyn:** hello",
            meetingDate: date, duration: 1920, apps: ["Microsoft Teams"],
            title: "Meeting join | Quarterly sync",
            windowTitles: ["Quarterly sync", "Meeting join | Quarterly sync"],
            speakerCount: 3,
            speakerSamples: [("Glyn", "audio/meeting-x-speakers/glyn.m4a")],
            userNotes: "", transcriptCleanup: nil)

        #expect(note.hasPrefix("---\n"))
        #expect(note.contains("title: \"Meeting join | Quarterly sync\""))
        #expect(note.contains("duration_minutes: 32"))
        #expect(note.contains("source: Microsoft Teams"))
        #expect(note.contains("speakers: 3"))
        #expect(note.contains("speaker_samples:\n  \"Glyn\": \"audio/meeting-x-speakers/glyn.m4a\""))
        #expect(note.contains("window_titles:\n  - \"Quarterly sync\""))
        #expect(note.contains("status: raw-transcript"))
        #expect(note.contains("# Meeting join | Quarterly sync"))
        #expect(note.contains("## Transcript\n\n**Glyn:** hello"))
        #expect(!note.contains("has_live_notes"))
        #expect(!note.contains("transcript_cleanup"))
    }

    @Test func yamlQuotingEscapesEmbeddedQuotesAndNewlines() {
        let note = TranscriptNote.markdown(
            transcript: "t", meetingDate: date, duration: 0, apps: [],
            title: "The \"big\" review",
            windowTitles: ["Line\nbreak title"])
        #expect(note.contains("title: \"The \\\"big\\\" review\""))
        #expect(note.contains("  - \"Line break title\""))
    }

    @Test func liveNotesSectionPrecedesTranscriptAndSetsFlag() throws {
        let note = TranscriptNote.markdown(
            transcript: "**Glyn:** hello", meetingDate: date, duration: 60,
            apps: [], userNotes: "Follow up with Alice about budget")
        #expect(note.contains("has_live_notes: true"))
        let notesRange = try #require(note.range(of: "## Notes (taken live during the meeting)"))
        let transcriptRange = try #require(note.range(of: "## Transcript"))
        #expect(notesRange.lowerBound < transcriptRange.lowerBound)
        #expect(note.contains("Follow up with Alice about budget"))
    }

    @Test func cleanupMarkerAppearsWhenRepaired() {
        let note = TranscriptNote.markdown(
            transcript: "t", meetingDate: date, duration: 0, apps: [],
            transcriptCleanup: "auto (on-device model)")
        #expect(note.contains("transcript_cleanup: \"auto (on-device model)\""))
    }

    @Test func fallbackTitleAndSourceForManualRecordings() {
        let note = TranscriptNote.markdown(
            transcript: "t", meetingDate: date, duration: 0, apps: [])
        #expect(note.contains("source: manual recording"))
        #expect(note.contains("# Meeting 20"))
    }
}

/// Config decode compatibility: configs written by older builds must load,
/// with the newer knobs falling back to sensible defaults.
struct ConfigCompatibilityTests {
    @Test func oldConfigDecodesWithDefaults() throws {
        let old = """
        {"notesFolder": "/tmp/notes", "audioFolder": "/tmp/audio",
         "keepAudio": true, "localeIdentifier": "en_GB"}
        """
        let config = try JSONDecoder().decode(Config.self, from: Data(old.utf8))
        #expect(config.effectiveAutoStopGrace == 30)
        #expect(config.effectiveWhisperModel == "large-v3-v20240930_turbo")
        #expect(config.effectiveDiarization)
        #expect(abs(config.effectiveVoiceMatchThreshold - 0.6) < 0.0001)
        #expect(config.effectiveTranscriptRepair)
        #expect(config.vocabulary == nil)
    }

    @Test func unknownKeysFromNewerBuildsAreIgnored() throws {
        let futuristic = """
        {"notesFolder": "/tmp/n", "audioFolder": "/tmp/a", "keepAudio": false,
         "localeIdentifier": "en_US", "summaryEngine": "apple",
         "voiceMatchThreshold": 0.75}
        """
        let config = try JSONDecoder().decode(Config.self, from: Data(futuristic.utf8))
        #expect(abs(config.effectiveVoiceMatchThreshold - 0.75) < 0.0001)
        #expect(!config.keepAudio)
    }
}
