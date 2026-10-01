import Foundation

/// Cluster hygiene between diarization and everything that trusts its
/// labels: the transcript, the speaker samples, and the voice catalogue.
///
/// Diarization answers "how many distinct voice-like things are here", and
/// on an isolated channel that is not the same as "how many people spoke".
/// A 77-minute two-person call on 2026-09-10 came out with four speakers:
/// the remote side's channel had been cut into the real voice plus two
/// clusters of sub-second interjections and Whisper's silence hallucinations,
/// and the catalogue then gave each splinter someone else's name. Nothing in
/// the fragments' embeddings links them to their owner (cosine 0.07–0.27 in
/// the eval pairs), so the rules here work from how much and how briefly a
/// cluster speaks, never from voice similarity.
extension Transcriber {

    /// How much a diarized voice actually spoke.
    struct VoiceStats: Equatable {
        var total: Double = 0
        var longest: Double = 0
        var segments = 0
    }

    static func voiceStats(_ segments: [Diarizer.SpeakerSegment]) -> [String: VoiceStats] {
        var stats: [String: VoiceStats] = [:]
        for segment in segments {
            let duration = max(0, segment.end - segment.start)
            var entry = stats[segment.speaker] ?? VoiceStats()
            entry.total += duration
            entry.longest = max(entry.longest, duration)
            entry.segments += 1
            stats[segment.speaker] = entry
        }
        return stats
    }

    struct SplinterMerge: Equatable {
        let splinter: String
        let into: String
        let share: Double
        let longest: Double
    }

    /// Folds splinter clusters back into the channel's real voices.
    ///
    /// A splinter holds a sliver of the channel's speech and never a
    /// sustained stretch of it: a few seconds of "yep", "thank you", or a
    /// throat-clear that the clustering could not place. "Sliver" is judged
    /// both relative to the channel and in absolute terms — seven seconds
    /// is a sliver of a five-minute standup too, even though it is 5% of
    /// it. A person who spoke that little is indistinguishable from noise
    /// anyway, and the cost of the two mistakes is lopsided — a real quiet
    /// participant folded into the main voice loses a label on a handful of
    /// words, while a splinter left standing becomes a phantom participant
    /// with a name.
    ///
    /// Each splinter goes to the substantial voice its embedding is closest
    /// to (with one substantial voice on the channel, that is simply it). The
    /// target's embedding is left alone: the fragments' voiceprint is exactly
    /// the part that was unreliable.
    static func absorbSplinters(
        segments: [Diarizer.SpeakerSegment],
        embeddings: [String: [Float]],
        maxShare: Double = 0.05,
        maxTotal: Double = 15,
        maxLongestSegment: Double = 8
    ) -> (segments: [Diarizer.SpeakerSegment], embeddings: [String: [Float]], merges: [SplinterMerge]) {
        let stats = voiceStats(segments)
        let channelTotal = stats.values.reduce(0) { $0 + $1.total }
        guard channelTotal > 0 else { return (segments, embeddings, []) }

        var splinters: [(label: String, share: Double, longest: Double)] = []
        var substantial: [String] = []
        for (label, entry) in stats {
            let share = entry.total / channelTotal
            if entry.longest < maxLongestSegment, share < maxShare || entry.total < maxTotal {
                splinters.append((label, share, entry.longest))
            } else {
                substantial.append(label)
            }
        }
        guard !splinters.isEmpty, !substantial.isEmpty else { return (segments, embeddings, []) }

        var target: [String: String] = [:]
        var merges: [SplinterMerge] = []
        for splinter in splinters.sorted(by: { $0.label < $1.label }) {
            let chosen: String
            if let embedding = embeddings[splinter.label],
               let best = substantial
                   .compactMap({ label -> (String, Double)? in
                       embeddings[label].map { (label, SpeakerCatalog.cosineSimilarity(embedding, $0)) }
                   })
                   .max(by: { ($0.1, $1.0) < ($1.1, $0.0) }) {
                chosen = best.0
            } else {
                // No usable embedding: the voice that dominates the channel.
                chosen = substantial.max { (stats[$0]!.total, $1) < (stats[$1]!.total, $0) }!
            }
            target[splinter.label] = chosen
            merges.append(SplinterMerge(
                splinter: splinter.label, into: chosen, share: splinter.share, longest: splinter.longest))
        }

        let merged = segments.map { segment in
            target[segment.speaker].map {
                Diarizer.SpeakerSegment(speaker: $0, start: segment.start, end: segment.end)
            } ?? segment
        }
        let keptEmbeddings = embeddings.filter { target[$0.key] == nil }
        return (merged, keptEmbeddings, merges)
    }

    /// Whether a voice spoke enough to be identified or remembered. The
    /// catalogue is only as good as the voiceprints in it: a record made from
    /// two seconds of fragments once matched every other channel's fragment
    /// cluster at 0.8+, putting one person's name into sixty notes.
    static func isCatalogueWorthy(
        _ stats: VoiceStats, minTotal: Double = 10, minLongestSegment: Double = 3
    ) -> Bool {
        stats.total >= minTotal && stats.longest >= minLongestSegment
    }

    /// Whisper's stock outputs over non-speech audio. Only ever dropped when
    /// diarization heard nobody speaking there — a real "thank you" sits on
    /// top of a diarized segment and is kept.
    static let stockHallucinations: Set<String> = [
        "thank you", "thanks", "thank you bye", "thank you very much",
        "thanks for watching", "you", "bye", "bye bye", "okay", "so",
        "hmm", "mm", "mm hmm", "uh", "um",
    ]

    /// Drops stock hallucinations that sit over silence. Whisper stretches
    /// them across the whole gap, so a segment that barely brushes real
    /// speech at one end still counts as silence.
    static func droppingStockPhrasesOverSilence(
        whisper: [(start: Double, end: Double, text: String)],
        diarized: [Diarizer.SpeakerSegment],
        minSpeechFraction: Double = 0.2
    ) -> [(start: Double, end: Double, text: String)] {
        // Without diarization there is no notion of silence to judge by.
        guard !diarized.isEmpty else { return whisper }
        return whisper.filter { segment in
            guard stockHallucinations.contains(normalized(segment.text)) else { return true }
            let duration = max(0.1, segment.end - segment.start)
            var covered = 0.0
            for speech in diarized {
                covered += max(0, min(segment.end, speech.end) - max(segment.start, speech.start))
            }
            return covered / duration >= minSpeechFraction
        }
    }

    // MARK: Pipeline wrappers (log what was done, in the channel's terms)

    static func withoutSplinters(_ outcome: Diarizer.Outcome?, channel: String) -> Diarizer.Outcome? {
        guard let outcome else { return nil }
        let result = absorbSplinters(segments: outcome.segments, embeddings: outcome.meanEmbeddings)
        for merge in result.merges {
            Log.info(String(
                format: "%@ channel: %@ is a splinter (%.0f%% of the speech, longest segment %.1fs) — folded into %@",
                channel, merge.splinter, merge.share * 100, merge.longest, merge.into))
        }
        return Diarizer.Outcome(segments: result.segments, meanEmbeddings: result.embeddings)
    }

    static func catalogueWorthy(
        _ embeddings: [String: [Float]], stats: [String: VoiceStats]
    ) -> [String: [Float]] {
        embeddings.filter { label, _ in
            guard let entry = stats[label], isCatalogueWorthy(entry) else {
                Log.info(String(
                    format: "%@ spoke too little to identify (%.0fs, longest %.1fs) — left unnamed and not catalogued",
                    label, stats[label]?.total ?? 0, stats[label]?.longest ?? 0))
                return false
            }
            return true
        }
    }

    static func droppingStockPhrasesOverSilence(
        whisper: [(start: Double, end: Double, text: String)],
        diarized: [Diarizer.SpeakerSegment],
        log channel: String
    ) -> [(start: Double, end: Double, text: String)] {
        let kept = droppingStockPhrasesOverSilence(whisper: whisper, diarized: diarized)
        if kept.count != whisper.count {
            Log.info("\(channel) channel: dropped \(whisper.count - kept.count) stock phrase(s) Whisper produced over silence")
        }
        return kept
    }
}
