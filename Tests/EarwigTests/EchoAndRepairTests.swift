import Foundation
import Testing

@testable import EarwigKit

/// Cross-channel echo suppression. The rules exist because the embedding
/// match is symmetric: when the far end's mics send your own voice back, your
/// mic cluster matches a system cluster and the naive rule deletes your whole
/// side of the conversation (2026-07-29: all 757 mic segments).
struct EchoSuppressionTests {
    /// Two embeddings that match each other strongly, and one that doesn't.
    static let voiceA: [Float] = [1, 0, 0, 0]
    static let voiceB: [Float] = [0, 1, 0, 0]

    @Test func remoteVoiceLeakingIntoTheMicIsStillDropped() {
        let decision = Transcriber.echoDecision(
            micEmbeddings: ["Speaker 2": Self.voiceA, "Speaker 3": Self.voiceB],
            systemEmbeddings: ["Speaker 1": Self.voiceA],
            // Speaker 3 does most of the talking, so Speaker 2 is a guest.
            micDurations: ["Speaker 2": 5, "Speaker 3": 100])
        #expect(decision.labels == ["Speaker 2"])
        #expect(decision.refusedFraction == nil)
    }

    @Test func theVoiceThatOwnsTheMicIsNeverAnEcho() {
        // The local speaker's voice comes back through the far end's mics and
        // matches the system channel — the exact 2026-07-29 shape.
        let decision = Transcriber.echoDecision(
            micEmbeddings: ["Speaker 4": Self.voiceA],
            systemEmbeddings: ["Speaker 1": Self.voiceA],
            micDurations: ["Speaker 4": 600])
        #expect(decision.labels.isEmpty)
        #expect(decision.protectedLocal == "Speaker 4")
    }

    @Test func suppressionThatWouldSilenceMostOfTheMicIsRefused() {
        // Every mic voice matches something on the system channel. Even with
        // the dominant one protected, dropping the rest would take most of
        // the channel — so the whole suppression is abandoned.
        let decision = Transcriber.echoDecision(
            micEmbeddings: ["Speaker 2": Self.voiceA, "Speaker 3": Self.voiceA, "Speaker 4": Self.voiceB],
            systemEmbeddings: ["Speaker 1": Self.voiceA, "Speaker 5": Self.voiceB],
            micDurations: ["Speaker 2": 200, "Speaker 3": 200, "Speaker 4": 100])
        #expect(decision.labels.isEmpty)
        #expect(decision.refusedFraction != nil)
    }

    @Test func voicesBelowTheSimilarityThresholdAreLeftAlone() {
        let decision = Transcriber.echoDecision(
            micEmbeddings: ["Speaker 2": Self.voiceA],
            systemEmbeddings: ["Speaker 1": Self.voiceB],
            micDurations: ["Speaker 2": 10, "Speaker 3": 90])
        #expect(decision.labels.isEmpty)
        #expect(decision.protectedLocal == nil)
    }
}

/// Transcript-repair chunking. Pieces must reconstruct the source exactly —
/// anything else silently rewrites the meeting — and must stay inside the
/// on-device model's context window.
struct RepairChunkingTests {
    @Test func piecesReconstructTheSourceExactly() {
        let transcript = """
        **Glyn:** One two three. Four five six?

        **Speaker 2:** Something else entirely.

        **Glyn:** Back again.
        """
        #expect(TranscriptRepair.pieces(of: transcript).joined() == transcript)
    }

    @Test func aSingleOverlongTurnIsSplitRatherThanSentWhole() {
        // The old chunker only ever started a new chunk, so one long
        // monologue reached the model at full size and blew the window.
        let monologue = "**Glyn:** " + String(
            repeating: "This is a sentence of a fairly ordinary length. ", count: 200)
        let pieces = TranscriptRepair.pieces(of: monologue, budget: 500)
        #expect(pieces.count > 1)
        #expect(pieces.allSatisfy { $0.count <= 500 })
        #expect(pieces.joined() == monologue)
    }

    @Test func textWithNoSentenceBreaksStillFitsTheBudget() {
        let rambling = String(repeating: "word ", count: 400)
        let pieces = TranscriptRepair.pieces(of: rambling, budget: 300)
        #expect(pieces.allSatisfy { $0.count <= 300 })
        #expect(pieces.joined() == rambling)
    }

    @Test func responseBudgetLeavesRoomInsideTheContextWindow() {
        // instructions + prompt + reserved response must fit 4096 tokens.
        let piece = String(repeating: "a", count: 2000)
        let reserved = TranscriptRepair.estimatedTokens(piece) * 3 / 2 + 128
        let instructionsAllowance = 800
        #expect(TranscriptRepair.estimatedTokens(piece) + reserved + instructionsAllowance < 4096)
    }
}

/// The model answers trimmed, so each piece's own whitespace — which carries
/// the "\n\n" turn separators — has to survive the round trip.
struct RepairEnvelopeTests {
    @Test func envelopeRoundTripsExactly() {
        for text in ["\n\n**Glyn:** hello\n\n", "no whitespace", "  padded  ", "\n\n\n"] {
            let (leading, core, trailing) = TranscriptRepair.whitespaceEnvelope(text)
            #expect(leading + core + trailing == text)
        }
    }

    @Test func separatorsAreIsolatedFromTheCore() {
        let (leading, core, trailing) = TranscriptRepair.whitespaceEnvelope("**Glyn:** hi.\n\n")
        #expect(leading.isEmpty)
        #expect(core == "**Glyn:** hi.")
        #expect(trailing == "\n\n")
    }
}

struct RepairSafetyTests {
    private let original = "**Glyn:** so the deck aligns everyone\n\n**Sam:** yep agreed\n\n**Glyn:** good"

    @Test func aFaithfulRepairIsAccepted() {
        let candidate = "**Glyn:** So the deck aligns everyone.\n\n**Sam:** Yep, agreed.\n\n**Glyn:** Good."
        #expect(TranscriptRepair.isSafeRepair(original: original, candidate: candidate))
    }

    @Test func aRepairThatChangesTheCaseOfASpeakerIsRejected() {
        // Seen on 2026-09-10: six turns came back as "glyn" and "sam".
        let candidate = "**glyn:** So the deck aligns everyone.\n\n**sam:** Yep, agreed.\n\n**glyn:** Good."
        #expect(!TranscriptRepair.isSafeRepair(original: original, candidate: candidate))
    }

    @Test func aRepairThatSwapsSpeakersIsRejected() {
        let candidate = "**Sam:** So the deck aligns everyone.\n\n**Glyn:** Yep, agreed.\n\n**Glyn:** Good."
        #expect(!TranscriptRepair.isSafeRepair(original: original, candidate: candidate))
    }
}
