import Foundation

/// Diarized transcription pipeline for a single mixed track (mic + system merged).
/// Falls back to a plain text block when diarization is unavailable.
enum DiarizedTranscriber {
    /// The transcription result — each shape carries exactly its own payload.
    enum Output {
        case diarized(turns: [TranscriptSegment], speakers: [SpeakerLabel], profiles: [SpeakerProfile])
        case plain(text: String)

        /// The mode written to the note's frontmatter.
        var mode: DiarizationMode {
            switch self {
            case .diarized: return .full
            case .plain: return .none
            }
        }
    }

    /// Throws only if every tier fails, so the caller can preserve audio rather than write an empty note.
    static func run(audioURL: URL, config cfg: Config) async throws -> Output {
        if cfg.enableDiarization {
            do {
                return try await full(audioURL: audioURL, config: cfg)
            } catch {
                Log.info("Full diarization failed (\(error)); falling back to single block")
            }
        }
        return try await singleBlock(audioURL: audioURL, cfg: cfg)
    }

    private static func full(audioURL: URL, config cfg: Config) async throws -> Output {
        // Sequential (not concurrent): WhisperKit and FluidAudio are both large CoreML models.
        let diarization = try await Diarizer.diarize(
            audioURL: audioURL, clusteringThreshold: cfg.clusteringThreshold,
            minSpeechDuration: cfg.minSpeechDuration)
        let words = try await Transcriber.transcribeTimed(
            audioURL: audioURL, localeIdentifier: cfg.localeIdentifier)

        let aligned = SpeakerAlignment.assignSpeakers(
            words: words, speakerSegments: diarization.segments)

        let registry: VoiceRegistry
        do {
            registry = try VoiceRegistry.load(from: Config.voicesURL)
        } catch {
            Log.info("Could not load voice registry (\(error)); proceeding with no enrolled voices")
            registry = VoiceRegistry()
        }

        let clusters = buildClusters(aligned: aligned, profiles: diarization.profiles)
        let resolution = IdentityResolver.resolve(
            clusters: clusters, registry: registry,
            mergeThreshold: cfg.clusterMergeThreshold, matchThreshold: cfg.voiceMatchThreshold,
            minSpeakerSeconds: cfg.minSpeakerSeconds)

        let relabeled = relabel(aligned, using: resolution.labelByKey)
        let turns = SpeakerAlignment.mergeConsecutiveTurns(
            relabeled.sorted { ($0.start, $0.end) < ($1.start, $1.end) })
        let speakers = orderedSpeakers(in: turns)
        return .diarized(turns: turns, speakers: speakers, profiles: resolution.profiles)
    }

    private static func buildClusters(aligned: [TranscriptSegment],
                                      profiles: [SpeakerProfile]) -> [ResolvableCluster] {
        var firstStart: [Int: TimeInterval] = [:]
        for seg in aligned {
            if case .remote(let id) = seg.speaker {
                firstStart[id] = min(firstStart[id] ?? .greatestFiniteMagnitude, seg.start)
            }
        }
        return profiles.compactMap { p in
            guard case .remote(let id) = p.label, let emb = p.embedding else { return nil }
            return ResolvableCluster(
                key: "\(id)", embedding: emb,
                speechSeconds: p.speechSeconds, firstStart: firstStart[id] ?? .greatestFiniteMagnitude)
        }
    }

    /// Unresolved `.remote` turns (e.g. no usable voiceprint) become `.others` rather than
    /// leaking a raw cluster id that could collide with a resolver-assigned Speaker N.
    private static func relabel(_ turns: [TranscriptSegment],
                                using labelByKey: [String: SpeakerLabel]) -> [TranscriptSegment] {
        turns.map { seg in
            guard case .remote(let id) = seg.speaker else { return seg }
            let label = labelByKey["\(id)"] ?? .others
            return TranscriptSegment(speaker: label, start: seg.start, end: seg.end, text: seg.text)
        }
    }

    private static func singleBlock(audioURL: URL, cfg: Config) async throws -> Output {
        let text = try await Transcriber.transcribe(
            audioURL: audioURL, localeIdentifier: cfg.localeIdentifier)
        return .plain(text: text)
    }

    private static func orderedSpeakers(in turns: [TranscriptSegment]) -> [SpeakerLabel] {
        var seen: [SpeakerLabel] = []
        for t in turns where !seen.contains(t.speaker) { seen.append(t.speaker) }
        return seen
    }
}
