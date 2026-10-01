import Foundation

/// Deciding whether a diarized voice is someone in the catalogue.
///
/// Matching a cluster's mean voiceprint alone is not enough. On 2026-09-30
/// the remote channel of a review meeting came out as three voices for six
/// or more people: one cluster held several presenters taking the floor in
/// turn. The average of all of them sat 0.76 from the voiceprint of someone
/// who was not in the meeting — above the 0.6 match threshold — so 102
/// turns were written under their name.
///
/// So a name is only given when two more things hold:
///  - the cluster's own stretches of speech, checked one at a time, mostly
///    agree on who it is (a blend of six people does not), and
///  - the best match is clearly ahead of the next-best *other* person (two
///    voices sitting a hair apart is a coin toss, not an identification).
/// A voice that fails either check stays "Speaker N" and is not catalogued:
/// a blended or ambiguous voiceprint in the catalogue would go on to
/// mislabel future meetings.
extension Transcriber {

    /// A stretch of one voice's speech long enough to carry its own
    /// voiceprint. `weight` is how many analysis windows went into it — a
    /// proxy for how much of the voice's speech it stands for.
    struct VoiceprintBlock: Equatable {
        let weight: Double
        let embedding: [Float]
    }

    /// Groups a voice's per-window voiceprints (`Diarizer.Outcome.chunks`),
    /// in order, into blocks spanning at least `blockSeconds` of the
    /// meeting, each with the mean of its windows' voiceprints. A short tail
    /// joins the block before it. Presenters take the floor in turns of
    /// minutes, so 20-second blocks keep different people's turns apart
    /// while averaging enough windows for a stable voiceprint.
    static func voiceprintBlocks(
        _ chunks: [Diarizer.SpeakerSegment], speaker: String, blockSeconds: Double = 20
    ) -> [VoiceprintBlock] {
        var blocks: [(weight: Double, sum: [Float])] = []
        var blockStart: Double?
        var weight = 0.0
        var sum: [Float] = []
        for chunk in chunks where chunk.speaker == speaker {
            guard let embedding = chunk.embedding, !embedding.isEmpty else { continue }
            if sum.isEmpty { sum = [Float](repeating: 0, count: embedding.count) }
            guard embedding.count == sum.count else { continue }
            if let start = blockStart, chunk.start - start >= blockSeconds {
                blocks.append((weight, sum))
                weight = 0
                sum = [Float](repeating: 0, count: embedding.count)
                blockStart = nil
            }
            if blockStart == nil { blockStart = chunk.start }
            for i in sum.indices { sum[i] += embedding[i] }
            weight += 1
        }
        if weight > 0 {
            if !blocks.isEmpty, weight < blockSeconds / 4 {
                for i in sum.indices { blocks[blocks.count - 1].sum[i] += sum[i] }
                blocks[blocks.count - 1].weight += weight
            } else {
                blocks.append((weight, sum))
            }
        }
        return blocks.map { VoiceprintBlock(weight: $0.weight, embedding: $0.sum) }
    }

    /// The catalogue as identification sees it.
    struct CatalogueVoice {
        let id: UUID
        let name: String?
        let embedding: [Float]

        /// Records sharing a name are one person heard in different rooms;
        /// an unnamed record is its own (so far anonymous) person.
        var identity: String { name.map { "name:\($0)" } ?? "id:\(id.uuidString)" }
        var displayName: String { name ?? "unnamed voice \(id.uuidString.prefix(8))" }
    }

    struct Candidate: Equatable {
        let id: UUID
        let name: String?
        let identity: String
        let displayName: String
        let similarity: Double
    }

    /// One candidate per person — the best-matching record of each — best
    /// first.
    static func rankedCandidates(_ embedding: [Float], catalogue: [CatalogueVoice]) -> [Candidate] {
        var best: [String: Candidate] = [:]
        for voice in catalogue {
            let similarity = SpeakerCatalog.cosineSimilarity(embedding, voice.embedding)
            if similarity > (best[voice.identity]?.similarity ?? -2) {
                best[voice.identity] = Candidate(
                    id: voice.id, name: voice.name, identity: voice.identity,
                    displayName: voice.displayName, similarity: similarity)
            }
        }
        return best.values.sorted { ($0.similarity, $1.identity) > ($1.similarity, $0.identity) }
    }

    enum Identification: Equatable {
        /// Recognised: write the catalogued voice's name (if it has one) and
        /// link the note to that record.
        case recognised(Candidate)
        /// Nobody in the catalogue: catalogue it so it can be named later.
        case newVoice
        /// The two best people are too close to call.
        case ambiguous(best: Candidate, runnerUp: Candidate)
        /// The voice's own stretches disagree about who it is — most likely
        /// several people diarized as one. `support` is the share of the
        /// decided speech that agrees with the overall match.
        case mixed(best: Candidate, support: Double)
    }

    /// See the type comment. `blockFloor` is the similarity below which a
    /// block is taken as evidence *against* the match even when it matches
    /// nobody in the catalogue: speakers who were never catalogued must
    /// still be able to outvote a blended mean.
    static func identify(
        mean: [Float],
        blocks: [VoiceprintBlock],
        catalogue: [CatalogueVoice],
        threshold: Double,
        margin: Double = 0.1,
        minSupport: Double = 0.75,
        blockFloor: Double = 0.4
    ) -> Identification {
        let ranked = rankedCandidates(mean, catalogue: catalogue)
        guard let best = ranked.first, best.similarity >= threshold else { return .newVoice }
        if ranked.count > 1, best.similarity - ranked[1].similarity < margin {
            return .ambiguous(best: best, runnerUp: ranked[1])
        }
        guard let support = blockSupport(
            for: best, blocks: blocks, catalogue: catalogue,
            threshold: threshold, blockFloor: blockFloor) else { return .recognised(best) }
        return support >= minSupport ? .recognised(best) : .mixed(best: best, support: support)
    }

    /// Share of a voice's decided blocks that agree it is `candidate`, or nil
    /// when there is nothing to cross-check: a single block is the voice
    /// itself, and blocks too weak to say anything either way leave the mean
    /// as all there is to go on.
    static func blockSupport(
        for candidate: Candidate, blocks: [VoiceprintBlock], catalogue: [CatalogueVoice],
        threshold: Double, blockFloor: Double = 0.4
    ) -> Double? {
        guard blocks.count > 1 else { return nil }
        var agree = 0.0, disagree = 0.0
        for block in blocks {
            let ranked = rankedCandidates(block.embedding, catalogue: catalogue)
            let toCandidate = ranked.first { $0.identity == candidate.identity }?.similarity ?? -1
            if let top = ranked.first, top.similarity >= threshold {
                if top.identity == candidate.identity { agree += block.weight } else { disagree += block.weight }
            } else if toCandidate < blockFloor {
                disagree += block.weight
            }
            // Otherwise the block is undecided: too weak to name anyone,
            // too close to the candidate to count against it.
        }
        let decided = agree + disagree
        return decided > 0 ? agree / decided : nil
    }

    /// The catalogue snapshot `identify` works against.
    static func catalogueVoices() -> [CatalogueVoice] {
        SpeakerCatalog.shared.all().map {
            CatalogueVoice(id: $0.id, name: $0.name, embedding: $0.embedding)
        }
    }

    /// `identify`, logged in the pipeline's terms.
    static func identifyLogged(
        label: String, mean: [Float], chunks: [Diarizer.SpeakerSegment],
        catalogue: [CatalogueVoice], threshold: Double
    ) -> Identification {
        let result = identify(
            mean: mean, blocks: voiceprintBlocks(chunks, speaker: label),
            catalogue: catalogue, threshold: threshold)
        switch result {
        case .recognised(let match):
            if match.name?.isEmpty == false {
                Log.info("Recognised \(label) as \(match.displayName) (similarity \(String(format: "%.2f", match.similarity)))")
            } else {
                Log.info("\(label) matches an uncatalogued voice heard before (similarity \(String(format: "%.2f", match.similarity)))")
            }
        case .newVoice:
            break
        case .ambiguous(let best, let runnerUp):
            Log.info(String(
                format: "%@ is too close to call between %@ (%.2f) and %@ (%.2f) — left unnamed and not catalogued",
                label, best.displayName, best.similarity, runnerUp.displayName, runnerUp.similarity))
        case .mixed(let best, let support):
            Log.info(String(
                format: "%@ sounds like several people (overall match %@ %.2f, but only %.0f%% of its speech agrees) — left unnamed and not catalogued",
                label, best.displayName, best.similarity, support * 100))
        }
        return result
    }
}
