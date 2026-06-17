import Foundation
import Speech

/// On-device speech-to-text. Prefers WhisperKit (large-v3) for accuracy;
/// falls back to SFSpeechRecognizer when Whisper is unavailable.
enum Transcriber {
    /// Shared WhisperKit-backed engine. A single instance keeps the loaded model
    /// cached across calls (back-to-back meetings reuse it).
    private static let whisper = WhisperASR()

    enum TranscriberError: Error, LocalizedError {
        case localeUnsupported(String)
        case notAuthorized
        case empty

        var errorDescription: String? {
            switch self {
            case .localeUnsupported(let l): return "Speech model unavailable for locale \(l)"
            case .notAuthorized: return "Speech recognition permission denied"
            case .empty: return "Transcription produced no text"
            }
        }
    }

    static func prewarm(progressCallback: (@Sendable (Progress) -> Void)? = nil) async throws {
        try await whisper.prepareModel(progressCallback: progressCallback)
    }

    static func join(_ segments: [TimedSegment]) -> String {
        segments
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func transcribe(audioURL: URL, localeIdentifier: String) async throws -> String {
        let segments = try await transcribeTimed(audioURL: audioURL, localeIdentifier: localeIdentifier)
        let text = join(segments)
        guard !text.isEmpty else { throw TranscriberError.empty }
        return text
    }

    /// Prefers WhisperKit; falls back to SFSpeechRecognizer on failure.
    static func transcribeTimed(audioURL: URL, localeIdentifier: String) async throws -> [TimedSegment] {
        do {
            return try await whisper.transcribe(
                audioURL: audioURL, localeIdentifier: localeIdentifier)
        } catch {
            Log.info("WhisperKit transcription failed (\(error)); falling back to SFSpeechRecognizer")
        }
        let locale = Locale(identifier: localeIdentifier)
        return try await transcribeTimedLegacy(audioURL: audioURL, locale: locale)
    }

    // MARK: Fallback — SFSpeechRecognizer

    private static func transcribeTimedLegacy(audioURL: URL, locale: Locale) async throws -> [TimedSegment] {
        let status = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        guard status == .authorized else { throw TranscriberError.notAuthorized }
        guard let recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer() else {
            throw TranscriberError.localeUnsupported(locale.identifier)
        }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        return try await withCheckedThrowingContinuation { cont in
            var resumed = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !resumed else { return }
                if let error {
                    resumed = true
                    cont.resume(throwing: error)
                } else if let result, result.isFinal {
                    resumed = true
                    let segs = result.bestTranscription.segments.map { seg in
                        TimedSegment(
                            text: seg.substring,
                            start: seg.timestamp,
                            end: seg.timestamp + seg.duration
                        )
                    }
                    cont.resume(returning: segs)
                }
            }
        }
    }
}
