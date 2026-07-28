import Foundation
import Testing
import WhisperKit

@testable import EarwigKit

/// Regression tests built from real failures captured in production meetings
/// (the garble patterns and mis-hearings are verbatim; business content and
/// most names are sanitised — this repo is public).
struct CapturedRegressionTests {
    // 2026-07-28, cafe meeting: Whisper hallucinated "Jesus." repetition runs
    // over the Teams-muted microphone's ambience and attributed them to the
    // local speaker.
    @Test func capturedJesusRepetitionRunsAreFlagged() {
        for captured in ["Jesus. Jesus. Jesus. Jesus. Jesus. Jesus.",
                         "Jesus. Jesus. Jesus.",
                         "Thank you. Thank you. Thank you."] {
            #expect(Transcriber.isLikelyHallucination(TranscriptionSegment(text: captured)),
                    "should flag repetition run: \(captured)")
        }
    }

    // Same meeting: decode collapse produced replacement-character and token
    // loops; these arrive with degenerate compression ratios.
    @Test func capturedDecodeCollapseIsFlaggedByCompressionRatio() {
        let captured = TranscriptionSegment(
            text: ",????urturturturturturt't't't a.",
            compressionRatio: 4.8, noSpeechProb: 0.4)
        #expect(Transcriber.isLikelyHallucination(captured))
    }

    // The seeded dictionary was born from these exact captured mis-hearings.
    @Test func capturedMisHearingsAreCorrectedDeterministically() {
        let corrections = [
            (wrong: "glenn", right: "Glyn"),
            (wrong: "Zurb", right: "Azure"),
            (wrong: "servility", right: "observability"),
        ]
        let captured = "so glenn will take the servility work for the Zurb migration"
        let (fixed, count) = Vocabulary.applyCorrections(corrections, to: captured)
        #expect(fixed == "so Glyn will take the observability work for the Azure migration")
        #expect(count == 3)
    }

    // 2026-07-28, catch-up call on loudspeakers: the remote participant
    // leaked into the mic, Whisper transcribed both copies with small
    // differences, and strict containment missed the duplicate.
    @Test func capturedEchoVariantIsDetectedAsDuplicate() {
        #expect(Transcriber.isDuplicateText(
            "I think we should get the intro booked in for next week then",
            "i think we should get the intro booked for next week"))
    }

    // The repair model once renamed the section heading, which silently broke
    // downstream parsing of the note.
    @Test func capturedHeadingRenameIsRejectedByGuardrail() {
        let original = "## Transcript\n\n**Alice:** so the timeline looks fine"
        let renamed = "## Corrected Transcript\n\n**Alice:** so the timeline looks fine"
        #expect(!TranscriptRepair.isSafeRepair(original: original, candidate: renamed))
        #expect(TranscriptRepair.isSafeRepair(original: original, candidate: original))
    }

    // A repair that drops or invents speaker turns must never be accepted.
    @Test func repairChangingTurnStructureIsRejected() {
        let original = "**Alice:** the budget is fine\n\n**Bob:** agreed"
        #expect(!TranscriptRepair.isSafeRepair(
            original: original, candidate: "**Alice:** the budget is fine"))
        #expect(!TranscriptRepair.isSafeRepair(
            original: original,
            candidate: original + "\n\n**Carol:** I was never here"))
    }

    // Wildly rewritten content (summarisation creep) is rejected on length.
    @Test func repairRewritingLengthIsRejected() {
        let original = "**Alice:** " + String(repeating: "the plan is solid and we move ahead ", count: 8)
        #expect(!TranscriptRepair.isSafeRepair(
            original: original, candidate: "**Alice:** plan approved."))
    }

    @Test func speakerNamesParsedFromCapturedTranscriptShape() {
        let transcript = """
        **Alice Haywood:** a little bit bewildered actually at the moment

        **Glyn:** Yeah.

        **Speaker 3:** the cost control, the observability

        **Alice Haywood:** mess you up a little bit don't they
        """
        #expect(TranscriptRepair.speakerNames(in: transcript)
            == ["Alice Haywood", "Glyn", "Speaker 3"])
    }
}
