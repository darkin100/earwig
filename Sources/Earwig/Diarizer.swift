import AVFoundation
import CoreML
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
            // CPU + Neural Engine only — keep the GPU free for live meetings.
            let mlConfiguration = MLModelConfiguration()
            mlConfiguration.computeUnits = .cpuAndNeuralEngine
            try await new.prepareModels(directory: modelsDir, configuration: mlConfiguration)
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

    /// Exports one short, loudness-normalized clip per speaker so a human can
    /// listen and identify who each anonymous "Speaker N" actually is.
    ///
    /// The sample is the longest of the speaker's segments that actually
    /// contains audible speech — diarization sometimes produces junk clusters
    /// of near-silence, and remote participants are often much quieter than
    /// the local microphone, so candidates are energy-checked and the chosen
    /// clip is peak-normalized before encoding.
    static func exportSamples(
        from audioURL: URL,
        segments: [SpeakerSegment],
        to directory: URL,
        maxSeconds: Double = 15
    ) async -> [SpeakerSample] {
        guard let source = try? AVAudioFile(forReading: audioURL) else {
            Log.info("Sample export: cannot open \(audioURL.lastPathComponent)")
            return []
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            Log.info("Could not create speaker samples dir: \(error)")
            return []
        }

        var bySpeaker: [String: [SpeakerSegment]] = [:]
        for segment in segments {
            bySpeaker[segment.speaker, default: []].append(segment)
        }
        // "Speaker 2" before "Speaker 10": sort numerically, names first.
        let ordered = bySpeaker.sorted {
            (Int($0.key.split(separator: " ").last ?? "") ?? -1, $0.key)
                < (Int($1.key.split(separator: " ").last ?? "") ?? -1, $1.key)
        }

        var samples: [SpeakerSample] = []
        for (speaker, speakerSegments) in ordered {
            let candidates = speakerSegments
                .sorted { ($0.end - $0.start) > ($1.end - $1.start) }
                .prefix(6)

            var chosen: AVAudioPCMBuffer?
            for candidate in candidates {
                guard let buffer = readSegment(
                    from: source, start: candidate.start,
                    duration: min(candidate.end - candidate.start, maxSeconds)) else { continue }
                if rms(of: buffer) >= 0.003 { // ≈ -50 dBFS: actual speech, not room tone
                    chosen = buffer
                    break
                }
            }
            guard let buffer = chosen else {
                Log.info("No audible sample for \(speaker) — skipping (likely a noise cluster)")
                continue
            }

            normalize(buffer, targetPeak: 0.85, maxGain: 24)

            let clipURL = directory.appendingPathComponent(safeFileName(for: speaker) + ".m4a")
            try? FileManager.default.removeItem(at: clipURL)
            do {
                let settings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: buffer.format.sampleRate,
                    AVNumberOfChannelsKey: buffer.format.channelCount,
                    AVEncoderBitRateKey: 96000,
                ]
                let output = try AVAudioFile(
                    forWriting: clipURL, settings: settings,
                    commonFormat: buffer.format.commonFormat,
                    interleaved: buffer.format.isInterleaved)
                try output.write(from: buffer)
                samples.append(SpeakerSample(speaker: speaker, url: clipURL))
            } catch {
                Log.info("Sample export failed for \(speaker): \(error)")
            }
        }
        Log.info("Exported \(samples.count) speaker sample clip(s) to \(directory.lastPathComponent)")
        return samples
    }

    private static func safeFileName(for speaker: String) -> String {
        speaker.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static func readSegment(
        from file: AVAudioFile, start: Double, duration: Double
    ) -> AVAudioPCMBuffer? {
        let sampleRate = file.processingFormat.sampleRate
        let startFrame = AVAudioFramePosition(max(0, start) * sampleRate)
        let frames = AVAudioFrameCount(max(0, duration) * sampleRate)
        guard frames > 0, startFrame < file.length,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames)
        else { return nil }
        do {
            file.framePosition = startFrame
            try file.read(into: buffer, frameCount: min(frames, AVAudioFrameCount(file.length - startFrame)))
        } catch {
            return nil
        }
        return buffer.frameLength > 0 ? buffer : nil
    }

    private static func rms(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return 0 }
        var sum: Double = 0
        let frames = Int(buffer.frameLength)
        for channel in 0..<Int(buffer.format.channelCount) {
            let data = channels[channel]
            for frame in 0..<frames {
                sum += Double(data[frame]) * Double(data[frame])
            }
        }
        return Float((sum / Double(frames * Int(buffer.format.channelCount))).squareRoot())
    }

    private static func normalize(_ buffer: AVAudioPCMBuffer, targetPeak: Float, maxGain: Float) {
        guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return }
        let frames = Int(buffer.frameLength)
        var peak: Float = 0
        for channel in 0..<Int(buffer.format.channelCount) {
            let data = channels[channel]
            for frame in 0..<frames {
                peak = max(peak, abs(data[frame]))
            }
        }
        guard peak > 0 else { return }
        let gain = min(targetPeak / peak, maxGain)
        guard gain > 1.01 else { return } // already loud enough
        for channel in 0..<Int(buffer.format.channelCount) {
            let data = channels[channel]
            for frame in 0..<frames {
                data[frame] *= gain
            }
        }
    }
}
