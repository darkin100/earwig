import Foundation

/// A per-meeting voice cluster (from one stream) awaiting identity resolution.
struct ResolvableCluster: Equatable {
    let key: String              // unique, e.g. "mic#1" / "sys#3"
    let embedding: [Float]
    let speechSeconds: TimeInterval
    let firstStart: TimeInterval
}

/// Merges voice clusters, matches against the registry, and assigns final labels.
enum IdentityResolver {
    struct Resolution {
        let labelByKey: [String: SpeakerLabel]   // cluster key -> final label
        let profiles: [SpeakerProfile]           // one per resolved identity
    }

    static func resolve(clusters: [ResolvableCluster], registry: VoiceRegistry,
                        mergeThreshold: Double, matchThreshold: Double,
                        minSpeakerSeconds: Double = 0) -> Resolution {
        guard !clusters.isEmpty else { return Resolution(labelByKey: [:], profiles: []) }

        // 1. Merge clusters that share a voiceprint.
        let groups = VoiceMatcher.mergeClusters(
            clusters.map(\.embedding), threshold: Float(mergeThreshold))

        // 2. Summarise each group: representative (longest speech), earliest start, totals.
        struct Group { var keys: [String]; let rep: [Float]; var firstStart: TimeInterval; var speech: TimeInterval }
        var summarised: [Group] = groups.map { idxs in
            let members = idxs.map { clusters[$0] }
            let rep = members.max { $0.speechSeconds < $1.speechSeconds }!
            return Group(
                keys: members.map(\.key),
                rep: rep.embedding,
                firstStart: members.map(\.firstStart).min() ?? 0,
                speech: members.reduce(0) { $0 + $1.speechSeconds })
        }

        // 2b. Fold tiny splinters into a similar substantial group, but only if acoustically
        //     close enough — a distinct brief speaker (one sentence) is kept, not absorbed.
        //     Skipped when every group is below the floor (don't fold everyone away).
        let substantial = summarised.filter { $0.speech >= minSpeakerSeconds }
        if minSpeakerSeconds > 0, !substantial.isEmpty, substantial.count < summarised.count {
            var kept = substantial
            for s in summarised where s.speech < minSpeakerSeconds {
                var bestIndex = -1
                var bestScore = -Float.greatestFiniteMagnitude
                for (i, k) in kept.enumerated() {
                    let score = VoiceMatcher.cosineSimilarity(s.rep, k.rep)
                    if score > bestScore { bestScore = score; bestIndex = i }
                }
                if bestIndex >= 0, bestScore >= Float(mergeThreshold) {
                    kept[bestIndex].keys += s.keys
                    kept[bestIndex].speech += s.speech
                    kept[bestIndex].firstStart = min(kept[bestIndex].firstStart, s.firstStart)
                } else {
                    kept.append(s) // distinct brief speaker — keep it
                }
            }
            summarised = kept
        }

        let ordered = summarised.sorted { $0.firstStart < $1.firstStart }
        var labelByKey: [String: SpeakerLabel] = [:]
        var profiles: [SpeakerProfile] = []
        var nextAnon = 1
        for group in ordered {
            let label: SpeakerLabel
            if let m = registry.match(group.rep, threshold: Float(matchThreshold)) {
                label = m.identity.isMe ? .me : .named(m.identity.name)
            } else {
                label = .remote(nextAnon)
                nextAnon += 1
            }
            for key in group.keys { labelByKey[key] = label }
            profiles.append(SpeakerProfile(label: label, embedding: group.rep, speechSeconds: group.speech))
        }
        return Resolution(labelByKey: labelByKey, profiles: profiles)
    }
}
