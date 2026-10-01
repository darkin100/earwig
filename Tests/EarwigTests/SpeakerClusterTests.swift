import Foundation
import Testing

@testable import EarwigKit

/// Cluster hygiene: the rules that stop a diarization splinter becoming a
/// phantom participant. Modelled on 2026-09-10 16:45 — a two-person call
/// whose remote channel came out as three voices, two of them named after
/// people who were not there.
struct SplinterAbsorptionTests {
    private typealias Seg = Diarizer.SpeakerSegment

    /// A 60-minute remote channel: one real voice plus the two kinds of
    /// splinter seen in practice.
    private func remoteChannel() -> [Seg] {
        var segments: [Seg] = []
        var t = 0.0
        for _ in 0..<40 {                       // Speaker 2: 40 x 45s = 1800s
            segments.append(Seg(speaker: "Speaker 2", start: t, end: t + 45)); t += 60
        }
        t = 5
        for _ in 0..<20 {                       // Speaker 1: 20 x 2s = 40s of "yep"
            segments.append(Seg(speaker: "Speaker 1", start: t, end: t + 2)); t += 120
        }
        segments.append(Seg(speaker: "Speaker 3", start: 30, end: 32.3))   // one "thank you"
        return segments
    }

    @Test func fragmentClustersAreFoldedIntoTheChannelsVoice() {
        let result = Transcriber.absorbSplinters(
            segments: remoteChannel(),
            embeddings: ["Speaker 1": [0.1, 0.9], "Speaker 2": [1, 0], "Speaker 3": [0.5, 0.5]])
        #expect(Set(result.segments.map(\.speaker)) == ["Speaker 2"])
        #expect(result.embeddings.keys.sorted() == ["Speaker 2"])
        #expect(result.merges.map(\.splinter) == ["Speaker 1", "Speaker 3"])
        #expect(result.merges.allSatisfy { $0.into == "Speaker 2" })
        // Nothing is lost, only relabelled.
        #expect(result.segments.count == remoteChannel().count)
    }

    @Test func aFewSecondsOfFragmentsIsASplinterEvenInAShortCall() {
        // The eval standup's remote channel: 7s of fragments is 5.2% of a
        // 134s channel — a sliver in any sense that matters.
        var segments: [Seg] = []
        for i in 0..<31 { segments.append(Seg(speaker: "Speaker 2", start: Double(i) * 4, end: Double(i) * 4 + 3.55)) }
        for i in 0..<4 { segments.append(Seg(speaker: "Speaker 3", start: 130 + Double(i) * 5, end: 130 + Double(i) * 5 + 4.25)) }
        segments.append(Seg(speaker: "Speaker 1", start: 150, end: 154.2))
        segments.append(Seg(speaker: "Speaker 1", start: 160, end: 162.8))
        let result = Transcriber.absorbSplinters(segments: segments, embeddings: [:])
        #expect(result.merges.map(\.splinter) == ["Speaker 1"])
        #expect(result.merges.first?.into == "Speaker 2")
    }

    @Test func aQuietButRealParticipantIsKept() {
        // 13% of the channel with a 35s stretch: Lisa on 2026-09-10 15:31.
        var segments = remoteChannel()
        segments.append(Seg(speaker: "Speaker 4", start: 100, end: 135))
        for i in 0..<12 {
            segments.append(Seg(speaker: "Speaker 4", start: 200 + Double(i) * 50, end: 220 + Double(i) * 50))
        }
        let result = Transcriber.absorbSplinters(segments: segments, embeddings: [:])
        #expect(Set(result.segments.map(\.speaker)) == ["Speaker 2", "Speaker 4"])
    }

    @Test func aBriefButSustainedVoiceIsNotASplinter() {
        // Someone who only says one thing, but says it for ten seconds.
        var segments = remoteChannel()
        segments.append(Seg(speaker: "Speaker 4", start: 100, end: 110))
        let result = Transcriber.absorbSplinters(segments: segments, embeddings: [:])
        #expect(result.segments.contains { $0.speaker == "Speaker 4" })
    }

    @Test func splintersGoToTheClosestSubstantialVoice() {
        var segments: [Seg] = []
        for i in 0..<20 {
            segments.append(Seg(speaker: "A", start: Double(i) * 100, end: Double(i) * 100 + 40))
            segments.append(Seg(speaker: "B", start: Double(i) * 100 + 50, end: Double(i) * 100 + 90))
        }
        segments.append(Seg(speaker: "C", start: 45, end: 47))
        let result = Transcriber.absorbSplinters(
            segments: segments,
            embeddings: ["A": [1, 0], "B": [0, 1], "C": [0.3, 0.8]])
        #expect(result.merges == [Transcriber.SplinterMerge(splinter: "C", into: "B", share: 2.0 / 1602, longest: 2)])
    }

    @Test func withoutEmbeddingsSplintersGoToTheDominantVoice() {
        var segments: [Seg] = []
        for i in 0..<20 {
            segments.append(Seg(speaker: "A", start: Double(i) * 100, end: Double(i) * 100 + 60))
            segments.append(Seg(speaker: "B", start: Double(i) * 100 + 70, end: Double(i) * 100 + 90))
        }
        segments.append(Seg(speaker: "C", start: 65, end: 67))
        let result = Transcriber.absorbSplinters(segments: segments, embeddings: [:])
        #expect(result.merges.first?.into == "A")
    }

    @Test func aChannelOfNothingButFragmentsIsLeftAlone() {
        // No substantial voice to fold into: better an honest "Speaker N"
        // than inventing an owner.
        let segments = (0..<5).map { Seg(speaker: "Speaker \($0 + 1)", start: Double($0) * 10, end: Double($0) * 10 + 1) }
        let result = Transcriber.absorbSplinters(segments: segments, embeddings: [:])
        #expect(result.merges.isEmpty)
        #expect(result.segments.count == 5)
    }

    @Test func anEmptyChannelIsFine() {
        let result = Transcriber.absorbSplinters(segments: [], embeddings: [:])
        #expect(result.segments.isEmpty && result.merges.isEmpty)
    }
}

struct CatalogueWorthinessTests {
    @Test func aVoiceNeedsBothVolumeAndASustainedStretch() {
        #expect(Transcriber.isCatalogueWorthy(.init(total: 120, longest: 6, segments: 30)))
        // The 2s-fragment cluster that became a 60-note phantom participant.
        #expect(!Transcriber.isCatalogueWorthy(.init(total: 12, longest: 2.3, segments: 8)))
        // Plenty of speech but never more than a word or two at once.
        #expect(!Transcriber.isCatalogueWorthy(.init(total: 40, longest: 2, segments: 20)))
        // One real sentence is not enough to fingerprint someone by.
        #expect(!Transcriber.isCatalogueWorthy(.init(total: 6, longest: 6, segments: 1)))
    }

    @Test func voiceStatsSummariseEachLabel() {
        let stats = Transcriber.voiceStats([
            .init(speaker: "A", start: 0, end: 5),
            .init(speaker: "A", start: 10, end: 12),
            .init(speaker: "B", start: 20, end: 21),
        ])
        #expect(stats["A"] == .init(total: 7, longest: 5, segments: 2))
        #expect(stats["B"] == .init(total: 1, longest: 1, segments: 1))
    }
}

struct SilenceHallucinationTests {
    private let speech: [Diarizer.SpeakerSegment] = [
        .init(speaker: "Speaker 1", start: 0, end: 10),
        .init(speaker: "Speaker 1", start: 30, end: 40),
    ]

    @Test func thankYouOverAGapIsDropped() {
        let kept = Transcriber.droppingStockPhrasesOverSilence(
            whisper: [(start: 12, end: 18, text: "Thank you.")], diarized: speech)
        #expect(kept.isEmpty)
    }

    @Test func aRealThankYouOnTopOfSpeechIsKept() {
        let kept = Transcriber.droppingStockPhrasesOverSilence(
            whisper: [(start: 8, end: 9, text: "Thank you.")], diarized: speech)
        #expect(kept.count == 1)
    }

    @Test func aStretchedHallucinationBrushingSpeechStillCountsAsSilence() {
        // Whisper spans the whole 20s gap; it touches the speech by 1s.
        let kept = Transcriber.droppingStockPhrasesOverSilence(
            whisper: [(start: 9, end: 29, text: "Thank you.")], diarized: speech)
        #expect(kept.isEmpty)
    }

    @Test func realWordsOverSilenceAreNeverDropped() {
        // Diarization can miss quiet speech; only stock phrases are suspect.
        let kept = Transcriber.droppingStockPhrasesOverSilence(
            whisper: [(start: 12, end: 18, text: "I think the roadmap slips a week")], diarized: speech)
        #expect(kept.count == 1)
    }

    @Test func withoutDiarizationNothingIsJudged() {
        let kept = Transcriber.droppingStockPhrasesOverSilence(
            whisper: [(start: 12, end: 18, text: "Thank you.")], diarized: [])
        #expect(kept.count == 1)
    }
}
