import Foundation
import Testing

@testable import EarwigKit

/// Speaker identification: when a diarized voice may be given a catalogued
/// person's name. Modelled on a 2026-09-30 review meeting whose remote
/// channel held six presenters in one cluster, and whose blended voiceprint
/// matched someone who was not there.
struct SpeakerIdentificationTests {
    private typealias Voice = Transcriber.CatalogueVoice
    private typealias Block = Transcriber.VoiceprintBlock

    /// Orthogonal unit voiceprints: each person is their own axis.
    private static func axis(_ i: Int, of n: Int = 8) -> [Float] {
        (0..<n).map { $0 == i ? 1 : 0 }
    }

    /// Mostly `i`, with a little of `j` — similarity to `i` well above any
    /// threshold, to `j` well below.
    private static func near(_ i: Int, leaning j: Int, by amount: Float = 0.2) -> [Float] {
        zip(axis(i), axis(j)).map { $0 + amount * $1 }
    }

    private let absent = Voice(id: UUID(), name: "Absent", embedding: axis(0))
    private let ana = Voice(id: UUID(), name: "Ana", embedding: axis(1))
    private let ben = Voice(id: UUID(), name: "Ben", embedding: axis(2))
    private let cal = Voice(id: UUID(), name: "Cal", embedding: axis(3))
    private var catalogue: [Voice] { [absent, ana, ben, cal] }

    private func blocks(_ embeddings: [[Float]]) -> [Block] {
        embeddings.map { Block(weight: 10, embedding: $0) }
    }

    @Test func aVoiceThatIsOnePersonThroughoutIsNamed() {
        let result = Transcriber.identify(
            mean: Self.near(1, leaning: 4),
            blocks: blocks(Array(repeating: Self.near(1, leaning: 5), count: 6)),
            catalogue: catalogue, threshold: 0.6)
        guard case .recognised(let match) = result else {
            Issue.record("expected recognised, got \(result)"); return
        }
        #expect(match.name == "Ana")
    }

    @Test func aBlendOfSeveralPresentersIsNotNamedAfterTheirAverage() {
        // The mean leans Absent; the stretches are Ana, Ben, Cal in turn.
        let result = Transcriber.identify(
            mean: Self.near(0, leaning: 1, by: 0.4),
            blocks: blocks([
                Self.axis(1), Self.axis(1), Self.axis(2), Self.axis(2),
                Self.axis(3), Self.axis(3), Self.axis(0),
            ]),
            catalogue: catalogue, threshold: 0.6)
        guard case .mixed(let best, let support) = result else {
            Issue.record("expected mixed, got \(result)"); return
        }
        #expect(best.name == "Absent")
        #expect(abs(support - 1.0 / 7.0) < 0.001)
    }

    @Test func presentersWhoWereNeverCataloguedStillOutvoteTheBlend() {
        // Stretches that match nobody, and sit far from Absent, count against Absent.
        let strangers = [Self.axis(5), Self.axis(6), Self.axis(7)]
        let result = Transcriber.identify(
            mean: Self.near(0, leaning: 5, by: 0.4),
            blocks: blocks(strangers + [Self.axis(0)]),
            catalogue: catalogue, threshold: 0.6)
        guard case .mixed = result else {
            Issue.record("expected mixed, got \(result)"); return
        }
    }

    @Test func weakStretchesNearTheMatchAbstainRatherThanObject() {
        // Two clean blocks, three noisy ones that are still recognisably Absent
        // (0.5: below the threshold, above the floor).
        let noisy: [Float] = [0.5, 0, 0, 0, 0.866, 0, 0, 0]
        let result = Transcriber.identify(
            mean: Self.axis(0),
            blocks: blocks([Self.axis(0), Self.axis(0), noisy, noisy, noisy]),
            catalogue: catalogue, threshold: 0.6)
        guard case .recognised = result else {
            Issue.record("expected recognised, got \(result)"); return
        }
    }

    @Test func aMostlyOnePersonVoiceKeepsItsName() {
        // 4 of 5 stretches agree: 80% support clears the bar.
        let result = Transcriber.identify(
            mean: Self.axis(0),
            blocks: blocks([Self.axis(0), Self.axis(0), Self.axis(0), Self.axis(0), Self.axis(1)]),
            catalogue: catalogue, threshold: 0.6)
        guard case .recognised = result else {
            Issue.record("expected recognised, got \(result)"); return
        }
    }

    @Test func twoPeopleTooCloseToCallAreNotNamed() {
        // Equidistant between Absent and Ana: 0.71 to each.
        let result = Transcriber.identify(
            mean: [1, 1, 0, 0, 0, 0, 0, 0], blocks: [],
            catalogue: catalogue, threshold: 0.6)
        guard case .ambiguous(let best, let runnerUp) = result else {
            Issue.record("expected ambiguous, got \(result)"); return
        }
        #expect(Set([best.name, runnerUp.name]) == ["Absent", "Ana"])
    }

    @Test func twoRecordsOfTheSamePersonAreNotARunnerUp() {
        // The same person catalogued from two meetings is not ambiguity.
        let absentAgain = Voice(id: UUID(), name: "Absent", embedding: Self.near(0, leaning: 4, by: 0.1))
        let result = Transcriber.identify(
            mean: Self.axis(0), blocks: [],
            catalogue: catalogue + [absentAgain], threshold: 0.6)
        guard case .recognised(let match) = result else {
            Issue.record("expected recognised, got \(result)"); return
        }
        #expect(match.name == "Absent")
    }

    @Test func noMatchAboveTheThresholdIsANewVoice() {
        let result = Transcriber.identify(
            mean: Self.axis(6), blocks: blocks([Self.axis(6), Self.axis(6)]),
            catalogue: catalogue, threshold: 0.6)
        #expect(result == .newVoice)
    }

    @Test func blocksGroupWindowsByTimeAndFoldAShortTail() {
        typealias Seg = Diarizer.SpeakerSegment
        var chunks: [Seg] = []
        // Windows every 2s from 0 to 48s for Speaker 1, interleaved with
        // another voice's that must be ignored.
        for i in 0...24 {
            let t = Double(i) * 2
            chunks.append(Seg(speaker: "Speaker 1", start: t, end: t + 10, embedding: Self.axis(i < 10 ? 0 : 1)))
            chunks.append(Seg(speaker: "Speaker 2", start: t, end: t + 10, embedding: Self.axis(7)))
        }
        let result = Transcriber.voiceprintBlocks(chunks, speaker: "Speaker 1")
        // 0–18s, 20–38s, then 40–48s (5 windows, a full-ish block of its own
        // since it is not under a quarter of the span).
        #expect(result.map(\.weight) == [10, 10, 5])
        #expect(SpeakerCatalog.cosineSimilarity(result[0].embedding, Self.axis(0)) > 0.99)
        #expect(SpeakerCatalog.cosineSimilarity(result[1].embedding, Self.axis(1)) > 0.99)

        // A 2-window tail joins the block before it.
        let short = Array(chunks.filter { $0.speaker == "Speaker 1" }.prefix(12))
        #expect(Transcriber.voiceprintBlocks(short, speaker: "Speaker 1").map(\.weight) == [12])
    }

    @Test func windowsWithoutVoiceprintsAreSkipped() {
        let chunks = [Diarizer.SpeakerSegment(speaker: "Speaker 1", start: 0, end: 10)]
        #expect(Transcriber.voiceprintBlocks(chunks, speaker: "Speaker 1").isEmpty)
    }
}
