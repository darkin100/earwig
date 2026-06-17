import Foundation

/// Pure voiceprint math: similarity, registry matching, and cluster grouping.
enum VoiceMatcher {
    /// Cosine similarity in [-1, 1]. Returns 0 for empty or zero-magnitude vectors,
    /// or mismatched lengths.
    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard !a.isEmpty, a.count == b.count else { return 0 }
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        for i in a.indices {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        guard na > 0, nb > 0 else { return 0 }
        return dot / (na.squareRoot() * nb.squareRoot())
    }

    /// Best identity for `embedding` among candidates (each candidate is that identity's
    /// list of sample voiceprints). Scores by the best sample per identity. Returns the
    /// winning index and its score, or nil if no identity scores >= threshold.
    static func bestMatch(_ embedding: [Float], among candidates: [[[Float]]],
                          threshold: Float) -> (index: Int, score: Float)? {
        var best: (index: Int, score: Float)?
        for (i, samples) in candidates.enumerated() {
            let score = samples.map { cosineSimilarity(embedding, $0) }.max() ?? -1
            if score >= threshold, score > (best?.score ?? -2) {
                best = (i, score)
            }
        }
        return best
    }

    /// Duration-weighted centroid (L2-normalized per segment, re-normalized at end).
    /// More stable than any single segment — short/noisy segments are naturally down-weighted.
    static func centroid(of embeddings: [[Float]], weights: [Double]) -> [Float]? {
        guard embeddings.count == weights.count else { return nil }
        var sum: [Float] = []
        for (vector, weight) in zip(embeddings, weights) {
            guard weight > 0, !vector.isEmpty else { continue }
            if sum.isEmpty { sum = Array(repeating: 0, count: vector.count) }
            guard vector.count == sum.count else { continue }
            let magnitude = vector.reduce(Float(0)) { $0 + $1 * $1 }.squareRoot()
            guard magnitude > 0 else { continue }
            let scale = Float(weight) / magnitude
            for i in vector.indices { sum[i] += vector[i] * scale }
        }
        let total = sum.reduce(Float(0)) { $0 + $1 * $1 }.squareRoot()
        guard total > 0 else { return nil }
        return sum.map { $0 / total }
    }

    /// Groups cluster embeddings whose pairwise similarity >= threshold (transitively,
    /// via union-find). Returns groups of original indices; each index appears once.
    static func mergeClusters(_ embeddings: [[Float]], threshold: Float) -> [[Int]] {
        let n = embeddings.count
        guard n > 0 else { return [] }
        var parent = Array(0..<n)
        func find(_ x: Int) -> Int {
            var r = x
            while parent[r] != r { r = parent[r] }
            var c = x
            while parent[c] != c { let next = parent[c]; parent[c] = r; c = next }
            return r
        }
        for i in 0..<n {
            for j in (i + 1)..<n where cosineSimilarity(embeddings[i], embeddings[j]) >= threshold {
                parent[find(j)] = find(i)
            }
        }
        var groups: [Int: [Int]] = [:]
        for i in 0..<n { groups[find(i), default: []].append(i) }
        return groups.values.sorted { ($0.min() ?? 0) < ($1.min() ?? 0) }
    }
}
