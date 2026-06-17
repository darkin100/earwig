import Foundation
import WhisperKit

/// WhisperKit (large-v3 turbo) actor. Caches the loaded model so back-to-back meetings
/// don't reload it. WhisperKit types are hidden behind Earwig's own value types.
actor WhisperASR {
    // large-v3 audio encoder + 4-layer decoder (vs 32) — near large-v3 accuracy, much faster.
    private static let modelVariant = "openai_whisper-large-v3-v20240930_turbo_632MB"

    enum WhisperASRError: Error, LocalizedError {
        case modelLoadFailed(String)
        case transcriptionFailed(String)
        case empty

        var errorDescription: String? {
            switch self {
            case .modelLoadFailed(let message):
                return "Failed to load Whisper model: \(message)"
            case .transcriptionFailed(let message):
                return "Whisper transcription failed: \(message)"
            case .empty:
                return "Whisper transcription produced no text"
            }
        }
    }

    private var cached: WhisperKit?

    func transcribe(audioURL: URL, localeIdentifier: String) async throws -> [TimedSegment] {
        let whisper = try await model()

        // VAD chunking splits the audio on speech boundaries so each decode window is a clean
        // utterance, not an arbitrary 30s slice that can start mid-sentence. This markedly
        // improves casing/punctuation consistency on long conversational meetings.
        let options = DecodingOptions(
            language: languageCode(from: localeIdentifier),
            wordTimestamps: true,
            chunkingStrategy: .vad
        )

        let results: [TranscriptionResult]
        do {
            results = try await whisper.transcribe(
                audioPath: audioURL.path,
                decodeOptions: options
            )
        } catch {
            throw WhisperASRError.transcriptionFailed(error.localizedDescription)
        }

        let segments = mapResults(results)
        guard !segments.isEmpty else {
            throw WhisperASRError.empty
        }
        return segments
    }

    // MARK: - Model

    /// Downloads + caches model (no-op if already loaded; skips download when HF cache hit).
    func prepareModel(progressCallback: (@Sendable (Progress) -> Void)? = nil) async throws {
        if cached != nil { return }
        Log.info("Downloading Whisper model (\(Self.modelVariant)) if needed…")
        do {
            let folder = try await WhisperKit.download(
                variant: Self.modelVariant, progressCallback: progressCallback)
            _ = try await loadAndCache(WhisperKitConfig(
                modelFolder: folder.path, verbose: false, load: true))
        } catch let error as WhisperASRError {
            throw error
        } catch {
            throw WhisperASRError.modelLoadFailed(error.localizedDescription)
        }
    }

    private func model() async throws -> WhisperKit {
        if let cached {
            return cached
        }
        Log.info("Downloading/loading Whisper model (\(Self.modelVariant)) if needed…")
        do {
            // load: true forces the model into memory now, so `modelVariant` reflects what
            // actually loaded (it defaults to .tiny until a model loads). verbose: false keeps
            // WhisperKit's own chatty logging out of our log.
            return try await loadAndCache(WhisperKitConfig(
                model: Self.modelVariant, verbose: false, load: true))
        } catch let error as WhisperASRError {
            throw error
        } catch {
            throw WhisperASRError.modelLoadFailed(error.localizedDescription)
        }
    }

    // Guards against WhisperKit silently falling back to a tiny model.
    private func loadAndCache(_ config: WhisperKitConfig) async throws -> WhisperKit {
        let whisper = try await WhisperKit(config)
        let loaded = "\(whisper.modelVariant)"
        Log.info("Loaded Whisper model: \(loaded)")
        // Never transcribe a meeting with the wrong (much weaker) model without surfacing it.
        guard !loaded.lowercased().contains("tiny") else {
            throw WhisperASRError.modelLoadFailed(
                "requested \(Self.modelVariant) but loaded '\(loaded)'")
        }
        cached = whisper
        return whisper
    }

    // MARK: - Language

    private func languageCode(from localeIdentifier: String) -> String? {
        let trimmed = localeIdentifier.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let prefix = trimmed.split(whereSeparator: { $0 == "_" || $0 == "-" }).first.map(String.init)
        guard let code = prefix, !code.isEmpty else { return nil }
        return code.lowercased()
    }

    // MARK: - Mapping

    private func mapResults(_ results: [TranscriptionResult]) -> [TimedSegment] {
        var timed: [TimedSegment] = []
        for result in results {
            for segment in result.segments {
                if let words = segment.words, !words.isEmpty {
                    for word in words {
                        timed.append(TimedSegment(
                            text: word.word,
                            start: Double(word.start),
                            end: Double(word.end)
                        ))
                    }
                } else {
                    timed.append(TimedSegment(
                        text: segment.text,
                        start: Double(segment.start),
                        end: Double(segment.end)
                    ))
                }
            }
        }
        return timed.sorted { $0.start < $1.start }
    }
}
