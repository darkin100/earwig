import AVFoundation
import Foundation
import Speech
import WhisperKit

/// On-device speech-to-text. Prefers Whisper (via WhisperKit, CoreML) for
/// quality on messy multi-speaker meeting audio; falls back to Apple's
/// SpeechAnalyzer / SFSpeechRecognizer if Whisper is unavailable or set to
/// "apple" in the config.
enum Transcriber {
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

    struct Output {
        let text: String
        /// Number of distinct speakers found by diarization; nil if diarization
        /// was disabled, failed, or the engine produced no timestamps.
        let speakerCount: Int?
        /// One short clip per speaker for human identification.
        var speakerSamples: [Diarizer.SpeakerSample] = []
    }

    static func transcribe(
        audioURL: URL, localeIdentifier: String,
        whisperModel: String = "large-v3-v20240930_turbo",
        diarize: Bool = true,
        sampleClipsDir: URL? = nil
    ) async throws -> Output {
        let locale = Locale(identifier: localeIdentifier)

        if whisperModel.lowercased() != "apple" {
            do {
                let output = try await transcribeWithWhisper(
                    audioURL: audioURL, locale: locale, model: whisperModel,
                    diarize: diarize, sampleClipsDir: sampleClipsDir)
                if !output.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return output
                }
                Log.info("Whisper produced no text; falling back to Apple speech")
            } catch {
                Log.info("WhisperKit failed (\(error)); falling back to Apple speech")
            }
        }

        // Apple fallback engines give no usable per-segment timestamps, so
        // speaker attribution is Whisper-only.
        if #available(macOS 26.0, *) {
            do {
                let text = try await transcribeWithAnalyzer(audioURL: audioURL, locale: locale)
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return Output(text: text, speakerCount: nil)
                }
            } catch {
                Log.info("SpeechAnalyzer failed (\(error)); falling back to SFSpeechRecognizer")
            }
        }
        let text = try await transcribeLegacy(audioURL: audioURL, locale: locale)
        return Output(text: text, speakerCount: nil)
    }

    // MARK: Whisper via WhisperKit

    // One pipeline is cached per app run: model load takes seconds and the
    // transcription queue is serialized, so reuse is safe and worthwhile.
    private static var cachedPipeline: WhisperKit?
    private static var cachedModelName: String?

    private static func whisperPipeline(model: String) async throws -> WhisperKit {
        if let pipeline = cachedPipeline, cachedModelName == model { return pipeline }

        // Keep models inside our own Application Support dir — never
        // ~/Documents, which would trigger a TCC folder prompt.
        let modelsDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Earwig/Models", isDirectory: true)
        try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)

        Log.info("Preparing Whisper model '\(model)' (first run downloads ~1.5 GB)...")
        let config = WhisperKitConfig(
            model: model,
            downloadBase: modelsDir,
            verbose: false,
            logLevel: .error,
            prewarm: true,
            load: true,
            download: true
        )
        let pipeline = try await WhisperKit(config)
        Log.info("Whisper model '\(model)' ready")
        cachedPipeline = pipeline
        cachedModelName = model
        return pipeline
    }

    private static func transcribeWithWhisper(
        audioURL: URL, locale: Locale, model: String, diarize: Bool, sampleClipsDir: URL?
    ) async throws -> Output {
        let pipeline = try await whisperPipeline(model: model)

        var options = DecodingOptions()
        options.task = .transcribe
        options.chunkingStrategy = .vad
        options.skipSpecialTokens = true
        if let language = locale.language.languageCode?.identifier {
            options.language = language
        }

        let results = try await pipeline.transcribe(
            audioPath: audioURL.path, decodeOptions: options)
        let plainText = results.map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !plainText.isEmpty else { throw TranscriberError.empty }

        guard diarize else { return Output(text: plainText, speakerCount: nil) }

        // Attribute Whisper's timestamped segments to diarized speakers.
        // Any diarization failure degrades to the plain transcript.
        do {
            let speakerSegments = try await Diarizer.diarize(audioURL: audioURL)
            guard !speakerSegments.isEmpty else {
                return Output(text: plainText, speakerCount: nil)
            }
            let whisperSegments = results
                .flatMap(\.segments)
                .map { (start: Double($0.start), end: Double($0.end),
                        text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines)) }
                .filter { !$0.text.isEmpty }
                .sorted { $0.start < $1.start }
            guard !whisperSegments.isEmpty else {
                return Output(text: plainText, speakerCount: nil)
            }

            let speakerCount = Set(speakerSegments.map(\.speaker)).count
            let attributed = attributedTranscript(
                whisperSegments: whisperSegments, speakerSegments: speakerSegments)
            var samples: [Diarizer.SpeakerSample] = []
            if let sampleClipsDir {
                samples = await Diarizer.exportSamples(
                    from: audioURL, segments: speakerSegments, to: sampleClipsDir)
            }
            return Output(text: attributed, speakerCount: speakerCount, speakerSamples: samples)
        } catch {
            Log.info("Diarization failed (\(error)); writing unattributed transcript")
            return Output(text: plainText, speakerCount: nil)
        }
    }

    /// Labels each transcript segment with the speaker whose diarized speech
    /// overlaps it most, then folds consecutive same-speaker segments into
    /// speaker turns.
    private static func attributedTranscript(
        whisperSegments: [(start: Double, end: Double, text: String)],
        speakerSegments: [Diarizer.SpeakerSegment]
    ) -> String {
        func dominantSpeaker(from start: Double, to end: Double) -> String? {
            var overlaps: [String: Double] = [:]
            for segment in speakerSegments {
                let overlap = min(end, segment.end) - max(start, segment.start)
                if overlap > 0 {
                    overlaps[segment.speaker, default: 0] += overlap
                }
            }
            return overlaps.max(by: { $0.value < $1.value })?.key
        }

        var turns: [(speaker: String, text: String)] = []
        var lastSpeaker = "Speaker 1"
        for segment in whisperSegments {
            let speaker = dominantSpeaker(from: segment.start, to: segment.end) ?? lastSpeaker
            lastSpeaker = speaker
            if var last = turns.last, last.speaker == speaker {
                last.text += " " + segment.text
                turns[turns.count - 1] = last
            } else {
                turns.append((speaker: speaker, text: segment.text))
            }
        }
        return turns.map { "**\($0.speaker):** \($0.text)" }.joined(separator: "\n\n")
    }

    // MARK: macOS 26 SpeechAnalyzer

    @available(macOS 26.0, *)
    private static func transcribeWithAnalyzer(audioURL: URL, locale: Locale) async throws -> String {
        let supported = await SpeechTranscriber.supportedLocales
        let useLocale = supported.first {
            $0.identifier(.bcp47) == locale.identifier(.bcp47)
        } ?? supported.first { $0.language.languageCode == locale.language.languageCode } ?? locale

        let transcriber = SpeechTranscriber(
            locale: useLocale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: []
        )

        // Download the on-device model if needed.
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            Log.info("Downloading speech model for \(useLocale.identifier)...")
            try await request.downloadAndInstall()
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let file = try AVAudioFile(forReading: audioURL)

        let collector = Task {
            var text = ""
            for try await result in transcriber.results where result.isFinal {
                text += String(result.text.characters)
            }
            return text
        }

        if let lastSample = try await analyzer.analyzeSequence(from: file) {
            try await analyzer.finalizeAndFinish(through: lastSample)
        } else {
            await analyzer.cancelAndFinishNow()
        }

        let text = try await collector.value
        guard !text.isEmpty else { throw TranscriberError.empty }
        return text
    }

    // MARK: Fallback — SFSpeechRecognizer

    private static func transcribeLegacy(audioURL: URL, locale: Locale) async throws -> String {
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
                    cont.resume(returning: result.bestTranscription.formattedString)
                }
            }
        }
    }
}
