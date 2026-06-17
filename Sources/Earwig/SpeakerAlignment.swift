import Foundation

/// Pure functions that fuse ASR output with diarization clusters and group turns.
enum SpeakerAlignment {
    /// Length of the intersection of two time ranges (0 if disjoint).
    static func overlap(_ aStart: TimeInterval, _ aEnd: TimeInterval,
                        _ bStart: TimeInterval, _ bEnd: TimeInterval) -> TimeInterval {
        max(0, min(aEnd, bEnd) - max(aStart, bStart))
    }

    /// Assigns each word to its best-overlap cluster. Ties → lower id. No overlap → nearest midpoint.
    /// No clusters at all → cluster 1 (rather than dropping words).
    static func assignSpeakers(words: [TimedSegment],
                               speakerSegments: [SpeakerSegment]) -> [TranscriptSegment] {
        guard !speakerSegments.isEmpty else {
            return words.map {
                TranscriptSegment(speaker: .remote(1), start: $0.start, end: $0.end, text: $0.text)
            }
        }

        return words.map { word in
            let cluster = bestCluster(for: word, in: speakerSegments)
            return TranscriptSegment(
                speaker: .remote(cluster), start: word.start, end: word.end, text: word.text)
        }
    }

    private static func bestCluster(for word: TimedSegment, in segments: [SpeakerSegment]) -> Int {
        var bestId = segments[0].clusterId
        var bestOverlap = -1.0
        for seg in segments {
            let ov = overlap(word.start, word.end, seg.start, seg.end)
            if ov > bestOverlap || (ov == bestOverlap && seg.clusterId < bestId) {
                bestOverlap = ov
                bestId = seg.clusterId
            }
        }
        if bestOverlap > 0 { return bestId }

        // No overlap: nearest by midpoint distance.
        let wordMid = (word.start + word.end) / 2
        var nearestId = segments[0].clusterId
        var nearestDist = Double.greatestFiniteMagnitude
        for seg in segments {
            let segMid = (seg.start + seg.end) / 2
            let dist = abs(wordMid - segMid)
            if dist < nearestDist || (dist == nearestDist && seg.clusterId < nearestId) {
                nearestDist = dist
                nearestId = seg.clusterId
            }
        }
        return nearestId
    }

    /// Merges adjacent same-speaker segments into a single turn. Assumes input sorted by start.
    static func mergeConsecutiveTurns(_ segments: [TranscriptSegment]) -> [TranscriptSegment] {
        guard var current = segments.first else { return [] }
        var result: [TranscriptSegment] = []
        for seg in segments.dropFirst() {
            if seg.speaker == current.speaker {
                current = TranscriptSegment(
                    speaker: current.speaker,
                    start: current.start,
                    end: seg.end,
                    text: [current.text, seg.text]
                        .filter { !$0.isEmpty }
                        .joined(separator: " "))
            } else {
                result.append(current)
                current = seg
            }
        }
        result.append(current)
        return result
    }
}
