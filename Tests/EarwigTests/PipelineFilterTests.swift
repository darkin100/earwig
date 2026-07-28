import Foundation
import Testing
import WhisperKit

@testable import EarwigKit

/// The Whisper hallucination gates ("Jesus. Jesus. Jesus." over cafe noise)
/// and the cross-channel echo text guard.
struct PipelineFilterTests {
    private func segment(
        text: String = "perfectly normal speech about the roadmap",
        avgLogprob: Float = -0.3,
        compressionRatio: Float = 1.4,
        noSpeechProb: Float = 0.05
    ) -> TranscriptionSegment {
        TranscriptionSegment(
            text: text, avgLogprob: avgLogprob,
            compressionRatio: compressionRatio, noSpeechProb: noSpeechProb)
    }

    @Test func normalSpeechPasses() {
        #expect(!Transcriber.isLikelyHallucination(segment()))
    }

    @Test func nonSpeechWithLowConfidenceIsDropped() {
        #expect(Transcriber.isLikelyHallucination(
            segment(text: "Thank you.", avgLogprob: -1.2, noSpeechProb: 0.8)))
    }

    @Test func nonSpeechAloneIsKeptWhenConfident() {
        // High noSpeechProb but a confident decode: keep (quiet real speech).
        #expect(!Transcriber.isLikelyHallucination(
            segment(text: "yes exactly", avgLogprob: -0.2, noSpeechProb: 0.7)))
    }

    @Test func deeplyUnconfidentDecodeIsDropped() {
        #expect(Transcriber.isLikelyHallucination(segment(avgLogprob: -2.4)))
    }

    @Test func repetitionLoopByCompressionRatioIsDropped() {
        #expect(Transcriber.isLikelyHallucination(segment(compressionRatio: 3.1)))
    }

    @Test func repeatedSinglePhraseIsDropped() {
        #expect(Transcriber.isLikelyHallucination(
            segment(text: "Jesus. Jesus. Jesus. Jesus.")))
    }

    // MARK: Echo text guard

    @Test func exactDuplicateIsDetected() {
        #expect(Transcriber.isDuplicateText(
            "we should ship the proposal on Friday",
            "we should ship the proposal on Friday"))
    }

    @Test func fuzzyDuplicateFromRetranscriptionIsDetected() {
        // Whisper transcribes the two copies of the same audio differently.
        #expect(Transcriber.isDuplicateText(
            "I will take the observability work for the migration",
            "I'll take the observability work for migration"))
    }

    @Test func differentSentencesAreNotDuplicates() {
        #expect(!Transcriber.isDuplicateText(
            "we should ship the proposal on Friday",
            "the diarization models run on the neural engine"))
    }

    @Test func shortBackchannelsRequireContainment() {
        #expect(Transcriber.isDuplicateText("Yeah.", "yeah"))
        #expect(!Transcriber.isDuplicateText("Yeah okay.", "no chance"))
    }

    // MARK: Attribution

    @Test func segmentsAttributeToDominantOverlapSpeaker() {
        let diarized = [
            Diarizer.SpeakerSegment(speaker: "Speaker 1", start: 0, end: 2.5),
            Diarizer.SpeakerSegment(speaker: "Speaker 2", start: 2.5, end: 6),
        ]
        let whisper = [(start: 0.0, end: 2.0, text: "hello"),
                       (start: 2.0, end: 5.0, text: "world")]
        let result = Transcriber.attributed(
            whisper: whisper, diarized: diarized, fallbackLabel: "Me")
        #expect(result.map(\.speaker) == ["Speaker 1", "Speaker 2"])
    }

    @Test func uncoveredSegmentInheritsPreviousSpeaker() {
        let diarized = [Diarizer.SpeakerSegment(speaker: "Speaker 1", start: 0, end: 2)]
        let whisper = [(start: 0.0, end: 2.0, text: "covered"),
                       (start: 10.0, end: 12.0, text: "uncovered")]
        let result = Transcriber.attributed(
            whisper: whisper, diarized: diarized, fallbackLabel: "Me")
        #expect(result.map(\.speaker) == ["Speaker 1", "Speaker 1"])
    }

    @Test func openingUncoveredSegmentUsesFirstDiarizedVoiceNotFallback() {
        let diarized = [Diarizer.SpeakerSegment(speaker: "Speaker 1", start: 5, end: 9)]
        let whisper = [(start: 0.0, end: 1.0, text: "opening")]
        let result = Transcriber.attributed(
            whisper: whisper, diarized: diarized, fallbackLabel: "Me")
        #expect(result.first?.speaker == "Speaker 1")
    }

    @Test func fallbackLabelWhenNothingDiarized() {
        let result = Transcriber.attributed(
            whisper: [(start: 0.0, end: 1.0, text: "hi")],
            diarized: [], fallbackLabel: "Me")
        #expect(result.first?.speaker == "Me")
    }

    // MARK: Voice-embedding similarity (echo suppression / catalogue matching)

    @Test func cosineSimilarityIdentity() {
        #expect(abs(SpeakerCatalog.cosineSimilarity([1, 0, 2], [1, 0, 2]) - 1.0) < 0.0001)
    }

    @Test func cosineSimilarityOrthogonal() {
        #expect(abs(SpeakerCatalog.cosineSimilarity([1, 0], [0, 1])) < 0.0001)
    }

    @Test func cosineSimilarityMismatchedDimensionsIsInvalid() {
        #expect(SpeakerCatalog.cosineSimilarity([1, 0], [1, 0, 0]) == -1)
    }
}
