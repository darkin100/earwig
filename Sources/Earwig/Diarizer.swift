import Foundation
import FluidAudio

/// On-device speaker diarization. Isolates all FluidAudio types behind Earwig's
/// own value types so the rest of the app never imports FluidAudio.
enum Diarizer {
    enum DiarizerError: Error, LocalizedError {
        case noSpeech
        case modelLoadFailed(String)
        case audioConversionFailed(String)
        case diarizationFailed(String)

        var errorDescription: String? {
            switch self {
            case .noSpeech:
                return "No speech was detected in the recording."
            case .modelLoadFailed(let message):
                return "Failed to load diarization models: \(message)"
            case .audioConversionFailed(let message):
                return "Failed to read audio for diarization: \(message)"
            case .diarizationFailed(let message):
                return "Diarization failed: \(message)"
            }
        }
    }

    struct Result {
        let segments: [SpeakerSegment]  // 1-based cluster IDs, second-based times
        let profiles: [SpeakerProfile]  // one per cluster with voiceprint and speech time
    }

    /// Diarize an audio file fully on device.
    ///
    /// - Parameters:
    ///   - audioURL: a local audio file (any format/sample rate readable by AVFoundation).
    ///   - clusteringThreshold: speaker-separation threshold (0.5-0.9); lower yields more speakers.
    ///   - minSpeechDuration: shortest speech span to keep, in seconds.
    static func diarize(
        audioURL: URL,
        clusteringThreshold: Double,
        minSpeechDuration: Double
    ) async throws -> Result {
        let models = try await modelCache.models()

        let config = DiarizerConfig(
            clusteringThreshold: Float(clusteringThreshold),
            minSpeechDuration: Float(minSpeechDuration)
        )

        // Detached: audio resampling + CoreML/ANE is synchronous and multi-second.
        // Only Sendable values cross the boundary; DiarizerManager stays fully inside.
        return try await Task.detached(priority: .userInitiated) {
            let samples = try resampleSamples(from: audioURL)

            let manager = DiarizerManager(config: config)
            manager.initialize(models: models)

            let fluidResult: DiarizationResult
            do {
                fluidResult = try manager.performCompleteDiarization(samples)
            } catch {
                throw DiarizerError.diarizationFailed(error.localizedDescription)
            }

            guard !fluidResult.segments.isEmpty else {
                throw DiarizerError.noSpeech
            }

            return mapResult(fluidResult.segments)
        }.value
    }

    /// Downloads + caches the diarization models. No-op if already cached.
    /// FluidAudio has no download-progress callback — callers show an indeterminate indicator.
    static func prewarm() async throws {
        _ = try await modelCache.models()
    }

    // MARK: - Models

    /// Caches DiarizerModels so the CoreML load happens once; manager is recreated per call.
    private actor ModelCache {
        private var cached: DiarizerModels?

        func models() async throws -> DiarizerModels {
            if let cached {
                return cached
            }
            Log.info("Downloading/loading FluidAudio diarization models if needed")
            do {
                let loaded = try await DiarizerModels.downloadIfNeeded()
                cached = loaded
                return loaded
            } catch {
                throw DiarizerError.modelLoadFailed(error.localizedDescription)
            }
        }
    }

    private static let modelCache = ModelCache()

    // MARK: - Audio

    private static func resampleSamples(from audioURL: URL) throws -> [Float] {
        let converter = AudioConverter()
        do {
            return try converter.resampleAudioFile(audioURL)
        } catch {
            throw DiarizerError.audioConversionFailed(error.localizedDescription)
        }
    }

    // MARK: - Mapping

    /// Maps FluidAudio speaker ids to stable 1-based cluster ids in first-seen order.
    /// Voiceprint is a duration-weighted centroid (see `VoiceMatcher.centroid`), not a single segment.
    private static func mapResult(_ fluidSegments: [TimedSpeakerSegment]) -> Result {
        var clusterIds: [String: Int] = [:]
        var nextClusterId = 1

        var segments: [SpeakerSegment] = []
        var speechSeconds: [Int: TimeInterval] = [:]
        var embeddings: [Int: [[Float]]] = [:]  // folded into a centroid below
        var embeddingWeights: [Int: [Double]] = [:]

        for fluidSegment in fluidSegments {
            let clusterId: Int
            if let existing = clusterIds[fluidSegment.speakerId] {
                clusterId = existing
            } else {
                clusterId = nextClusterId
                clusterIds[fluidSegment.speakerId] = clusterId
                nextClusterId += 1
            }

            let start = TimeInterval(fluidSegment.startTimeSeconds)
            let end = TimeInterval(fluidSegment.endTimeSeconds)
            let duration = max(0, end - start)

            segments.append(SpeakerSegment(clusterId: clusterId, start: start, end: end))
            speechSeconds[clusterId, default: 0] += duration

            let embedding = fluidSegment.embedding
            if !embedding.isEmpty {
                embeddings[clusterId, default: []].append(embedding)
                embeddingWeights[clusterId, default: []].append(duration)
            }
        }

        let profiles = clusterIds.values.sorted().map { clusterId in
            let voiceprint = VoiceMatcher.centroid(
                of: embeddings[clusterId] ?? [],
                weights: embeddingWeights[clusterId] ?? [])
            return SpeakerProfile(
                label: .remote(clusterId),
                embedding: voiceprint,
                speechSeconds: speechSeconds[clusterId]!
            )
        }

        return Result(segments: segments, profiles: profiles)
    }
}
