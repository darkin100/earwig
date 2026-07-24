import AVFoundation
import FluidAudio
import Foundation

/// Speaker diarization — "who spoke when" — via FluidAudio's offline pipeline
/// (pyannote segmentation + WeSpeaker embeddings, CoreML, on-device).
/// Produces anonymous speaker labels ("Speaker 1", "Speaker 2", ...) numbered
/// by order of first appearance.
enum Diarizer {
    struct SpeakerSegment {
        let speaker: String
        let start: Double
        let end: Double
    }

    struct Outcome {
        let segments: [SpeakerSegment]
        /// Duration-weighted mean voice embedding per speaker label — the
        /// fingerprint used to match voices against the speaker catalogue.
        let meanEmbeddings: [String: [Float]]
    }

    // Models load once per app run; the transcription pipeline is serialized
    // so a single cached manager is safe.
    private static var manager: OfflineDiarizerManager?

    static func diarize(audioURL: URL) async throws -> Outcome {
        let mgr: OfflineDiarizerManager
        if let cached = manager {
            mgr = cached
        } else {
            let modelsDir = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Earwig/Models/Diarizer", isDirectory: true)
            try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)

            let new = OfflineDiarizerManager(config: .default)
            Log.info("Preparing diarization models (first run downloads them)...")
            try await new.prepareModels(directory: modelsDir)
            Log.info("Diarization models ready")
            manager = new
            mgr = new
        }

        let result = try await mgr.process(audioURL)

        // Renumber FluidAudio's speaker IDs by order of first appearance, and
        // accumulate a duration-weighted mean embedding per speaker.
        var order: [String: Int] = [:]
        var segments: [SpeakerSegment] = []
        var weightedSums: [String: [Float]] = [:]
        for segment in result.segments.sorted(by: { $0.startTimeSeconds < $1.startTimeSeconds }) {
            if order[segment.speakerId] == nil {
                order[segment.speakerId] = order.count + 1
            }
            let label = "Speaker \(order[segment.speakerId]!)"
            segments.append(SpeakerSegment(
                speaker: label,
                start: Double(segment.startTimeSeconds),
                end: Double(segment.endTimeSeconds)
            ))
            let weight = max(0.1, segment.endTimeSeconds - segment.startTimeSeconds)
            if !segment.embedding.isEmpty {
                var sum = weightedSums[label] ?? [Float](repeating: 0, count: segment.embedding.count)
                if sum.count == segment.embedding.count {
                    for i in 0..<sum.count { sum[i] += segment.embedding[i] * weight }
                    weightedSums[label] = sum
                }
            }
        }
        // Normalize to unit length (cosine similarity ignores scale, but unit
        // vectors keep the stored JSON well-behaved).
        var meanEmbeddings: [String: [Float]] = [:]
        for (label, sum) in weightedSums {
            let norm = sum.reduce(Float(0)) { $0 + $1 * $1 }.squareRoot()
            if norm > 0 {
                meanEmbeddings[label] = sum.map { $0 / norm }
            }
        }
        Log.info("Diarization found \(order.count) speaker(s) across \(segments.count) segments")
        return Outcome(segments: segments, meanEmbeddings: meanEmbeddings)
    }

    struct SpeakerSample {
        let speaker: String
        let url: URL
    }

    /// Exports one short audio clip per speaker — their longest contiguous
    /// segment, capped at `maxSeconds` — so a human can listen and identify
    /// who each anonymous "Speaker N" actually is.
    static func exportSamples(
        from audioURL: URL,
        segments: [SpeakerSegment],
        to directory: URL,
        maxSeconds: Double = 15
    ) async -> [SpeakerSample] {
        var longest: [String: SpeakerSegment] = [:]
        for segment in segments {
            let current = longest[segment.speaker]
            if current == nil || (segment.end - segment.start) > (current!.end - current!.start) {
                longest[segment.speaker] = segment
            }
        }
        guard !longest.isEmpty else { return [] }

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            Log.info("Could not create speaker samples dir: \(error)")
            return []
        }

        // "Speaker 2" before "Speaker 10": sort numerically.
        let ordered = longest.sorted {
            (Int($0.key.split(separator: " ").last ?? "") ?? 0)
                < (Int($1.key.split(separator: " ").last ?? "") ?? 0)
        }

        var samples: [SpeakerSample] = []
        for (speaker, segment) in ordered {
            let asset = AVURLAsset(url: audioURL)
            guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
                continue
            }
            let duration = min(segment.end - segment.start, maxSeconds)
            export.timeRange = CMTimeRange(
                start: CMTime(seconds: segment.start, preferredTimescale: 600),
                duration: CMTime(seconds: duration, preferredTimescale: 600))
            let clipURL = directory.appendingPathComponent(
                speaker.replacingOccurrences(of: " ", with: "-").lowercased() + ".m4a")
            try? FileManager.default.removeItem(at: clipURL)
            do {
                try await export.export(to: clipURL, as: .m4a)
                samples.append(SpeakerSample(speaker: speaker, url: clipURL))
            } catch {
                Log.info("Sample export failed for \(speaker): \(error)")
            }
        }
        Log.info("Exported \(samples.count) speaker sample clip(s) to \(directory.lastPathComponent)")
        return samples
    }
}
