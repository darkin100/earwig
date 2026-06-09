import AVFoundation
import Foundation
import Speech

/// On-device speech-to-text. Prefers the macOS 26 SpeechAnalyzer API
/// (designed for long-form audio); falls back to SFSpeechRecognizer.
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

    static func transcribe(audioURL: URL, localeIdentifier: String) async throws -> String {
        let locale = Locale(identifier: localeIdentifier)
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
