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

    static func transcribe(
        audioURL: URL, localeIdentifier: String, whisperModel: String = "large-v3-v20240930_turbo"
    ) async throws -> String {
        let locale = Locale(identifier: localeIdentifier)

        if whisperModel.lowercased() != "apple" {
            do {
                let text = try await transcribeWithWhisper(
                    audioURL: audioURL, locale: locale, model: whisperModel)
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return text }
                Log.info("Whisper produced no text; falling back to Apple speech")
            } catch {
                Log.info("WhisperKit failed (\(error)); falling back to Apple speech")
            }
        }

        if #available(macOS 26.0, *) {
            do {
                let text = try await transcribeWithAnalyzer(audioURL: audioURL, locale: locale)
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return text }
            } catch {
                Log.info("SpeechAnalyzer failed (\(error)); falling back to SFSpeechRecognizer")
            }
        }
        return try await transcribeLegacy(audioURL: audioURL, locale: locale)
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
        audioURL: URL, locale: Locale, model: String
    ) async throws -> String {
        let pipeline = try await whisperPipeline(model: model)

        var options = DecodingOptions()
        options.task = .transcribe
        options.chunkingStrategy = .vad
        if let language = locale.language.languageCode?.identifier {
            options.language = language
        }

        let results = try await pipeline.transcribe(
            audioPath: audioURL.path, decodeOptions: options)
        let text = results.map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw TranscriberError.empty }
        return text
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
