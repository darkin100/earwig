import AVFoundation
import CoreML
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
        var text: String
        /// Number of distinct speakers found by diarization; nil if diarization
        /// was disabled, failed, or the engine produced no timestamps.
        let speakerCount: Int?
        /// One short clip per speaker for human identification.
        var speakerSamples: [Diarizer.SpeakerSample] = []
        /// Catalogue record behind each transcript label, so the note can be
        /// linked for retroactive renames.
        var speakerRecords: [(label: String, recordID: UUID)] = []
        /// True when the on-device model applied context-aware repairs.
        var repaired = false
    }

    static func transcribe(
        audioURL: URL, localeIdentifier: String,
        whisperModel: String = "large-v3-v20240930_turbo",
        diarize: Bool = true,
        sampleClipsDir: URL? = nil,
        voiceMatchThreshold: Double = 0.6,
        channels: Recorder.ChannelFiles? = nil,
        repairTranscript: Bool = true
    ) async throws -> Output {
        var output = try await transcribeCore(
            audioURL: audioURL, localeIdentifier: localeIdentifier,
            whisperModel: whisperModel, diarize: diarize,
            sampleClipsDir: sampleClipsDir,
            voiceMatchThreshold: voiceMatchThreshold, channels: channels)

        // Deterministic dictionary corrections for known mis-hearings.
        let vocabulary = Vocabulary.current()
        if !vocabulary.corrections.isEmpty {
            let (corrected, count) = Vocabulary.applyCorrections(
                vocabulary.corrections, to: output.text)
            if count > 0 {
                output.text = corrected
                Log.info("Applied \(count) dictionary correction(s)")
            }
        }

        // Context-aware repair of obvious mis-recognitions, on-device.
        if repairTranscript, output.text.contains("**") {
            let names = TranscriptRepair.speakerNames(in: output.text)
            if let repaired = await TranscriptRepair.repair(
                transcript: output.text, speakerNames: names) {
                output = Output(
                    text: repaired, speakerCount: output.speakerCount,
                    speakerSamples: output.speakerSamples,
                    speakerRecords: output.speakerRecords, repaired: true)
            }
        }
        return output
    }

    private static func transcribeCore(
        audioURL: URL, localeIdentifier: String,
        whisperModel: String,
        diarize: Bool,
        sampleClipsDir: URL?,
        voiceMatchThreshold: Double,
        channels: Recorder.ChannelFiles?
    ) async throws -> Output {
        let locale = Locale(identifier: localeIdentifier)

        if whisperModel.lowercased() != "apple" {
            // Preferred: process mic and system channels separately. The
            // system channel diarizes cleanly (no local room noise beneath
            // remote voices) and the mic channel gives the catalogue a clean
            // voiceprint of the local speaker.
            if diarize, let channels,
               FileManager.default.fileExists(atPath: channels.mic.path),
               FileManager.default.fileExists(atPath: channels.system.path) {
                do {
                    let output = try await transcribeTwoChannel(
                        channels: channels, locale: locale, model: whisperModel,
                        sampleClipsDir: sampleClipsDir,
                        voiceMatchThreshold: voiceMatchThreshold)
                    if !output.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        return output
                    }
                    Log.info("Two-channel processing produced no text; falling back to merged audio")
                } catch {
                    Log.info("Two-channel processing failed (\(error)); falling back to merged audio")
                }
            }

            do {
                let output = try await transcribeWithWhisper(
                    audioURL: audioURL, locale: locale, model: whisperModel,
                    diarize: diarize, sampleClipsDir: sampleClipsDir,
                    voiceMatchThreshold: voiceMatchThreshold)
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

    // MARK: Two-channel processing (mic + system separately)

    struct AttributedSegment {
        var start: Double
        var end: Double
        let text: String
        var speaker: String
    }

    private static func transcribeTwoChannel(
        channels: Recorder.ChannelFiles, locale: Locale, model: String,
        sampleClipsDir: URL?, voiceMatchThreshold: Double
    ) async throws -> Output {
        // 1. Whisper each channel independently.
        let systemWhisper = try await whisperRawSegments(
            audioURL: channels.system, locale: locale, model: model)
        var micWhisper = try await whisperRawSegments(
            audioURL: channels.mic, locale: locale, model: model)

        // Energy gate for the mic channel: while the user is muted the mic
        // still records room ambience, which Whisper happily "transcribes".
        // Real speech into a nearby mic is far above the ambience floor.
        if let micFile = try? AVAudioFile(forReading: channels.mic) {
            let before = micWhisper.count
            micWhisper = micWhisper.filter { segment in
                guard let energy = Diarizer.speechEnergy(
                    file: micFile, start: segment.start, end: segment.end) else { return true }
                return energy >= 0.004
            }
            if micWhisper.count != before {
                Log.info("Energy gate dropped \(before - micWhisper.count) mic segment(s) below the speech floor")
            }
        }
        guard !(systemWhisper.isEmpty && micWhisper.isEmpty) else {
            throw TranscriberError.empty
        }
        Log.info("Two-channel: system \(systemWhisper.count) segments, mic \(micWhisper.count) segments")

        // 2. Diarize each channel (tolerating per-channel failure), then
        //    renumber speaker labels into one shared "Speaker N" space.
        let systemOutcome = try? await Diarizer.diarize(audioURL: channels.system)
        let micOutcome = try? await Diarizer.diarize(audioURL: channels.mic)

        var labelCount = 0
        func renumbered(_ outcome: Diarizer.Outcome?)
            -> (segments: [Diarizer.SpeakerSegment], embeddings: [String: [Float]]) {
            guard let outcome else { return ([], [:]) }
            var map: [String: String] = [:]
            var segments: [Diarizer.SpeakerSegment] = []
            for segment in outcome.segments.sorted(by: { $0.start < $1.start }) {
                if map[segment.speaker] == nil {
                    labelCount += 1
                    map[segment.speaker] = "Speaker \(labelCount)"
                }
                segments.append(Diarizer.SpeakerSegment(
                    speaker: map[segment.speaker]!, start: segment.start, end: segment.end))
            }
            var embeddings: [String: [Float]] = [:]
            for (old, embedding) in outcome.meanEmbeddings {
                if let new = map[old] { embeddings[new] = embedding }
            }
            return (segments, embeddings)
        }
        var (systemSegments, systemEmbeddings) = renumbered(systemOutcome)
        var (micSegments, micEmbeddings) = renumbered(micOutcome)

        // Cross-channel echo suppression: a mic-channel voice whose embedding
        // matches a system-channel voice IS that remote participant leaking
        // through the speakers into the microphone. The system channel is
        // authoritative for remote voices — drop the mic cluster entirely so
        // it can't duplicate text or spawn a phantom catalogue entry.
        var echoLabels: Set<String> = []
        for (micLabel, micEmbedding) in micEmbeddings {
            var best: (label: String, similarity: Double)?
            for (systemLabel, systemEmbedding) in systemEmbeddings {
                let similarity = SpeakerCatalog.cosineSimilarity(micEmbedding, systemEmbedding)
                if similarity > (best?.similarity ?? 0) {
                    best = (systemLabel, similarity)
                }
            }
            if let best, best.similarity >= 0.65 {
                echoLabels.insert(micLabel)
                Log.info("Mic voice \(micLabel) is an echo of \(best.label) (similarity \(String(format: "%.2f", best.similarity))) — dropping it")
            }
        }
        micEmbeddings = micEmbeddings.filter { !echoLabels.contains($0.key) }

        var allEmbeddings = systemEmbeddings.merging(micEmbeddings) { a, _ in a }

        // 3. Match voices against the catalogue; rename matched+named labels.
        var displayNames: [String: String] = [:]
        var matchedIDs: [String: UUID] = [:]
        for (label, embedding) in allEmbeddings {
            if let match = SpeakerCatalog.shared.bestMatch(
                embedding: embedding, threshold: voiceMatchThreshold) {
                matchedIDs[label] = match.id
                if let name = match.name, !name.isEmpty {
                    displayNames[label] = name
                    Log.info("Recognised \(label) as \(name) (similarity \(String(format: "%.2f", match.similarity)))")
                }
            }
        }
        func renamed(_ segments: [Diarizer.SpeakerSegment]) -> [Diarizer.SpeakerSegment] {
            segments.map { segment in
                displayNames[segment.speaker].map {
                    Diarizer.SpeakerSegment(speaker: $0, start: segment.start, end: segment.end)
                } ?? segment
            }
        }
        systemSegments = renamed(systemSegments)
        micSegments = renamed(micSegments)

        // 4. Attribute each channel's transcript to its own diarized voices,
        //    then shift the mic timeline onto the system timeline.
        var systemAttributed = attributed(whisper: systemWhisper, diarized: systemSegments,
                                          fallbackLabel: "Remote speaker")
        var micAttributed = attributed(whisper: micWhisper, diarized: micSegments,
                                       fallbackLabel: "Me")
        // Text spoken by an echo cluster goes with it.
        if !echoLabels.isEmpty {
            let before = micAttributed.count
            micAttributed = micAttributed.filter { !echoLabels.contains($0.speaker) }
            if micAttributed.count != before {
                Log.info("Dropped \(before - micAttributed.count) mic segment(s) belonging to echo voices")
            }
        }
        for i in micAttributed.indices {
            micAttributed[i].start += channels.micOffset
            micAttributed[i].end += channels.micOffset
        }

        // 5. Echo guard, text level: catches residual duplicates the embedding
        //    check can't (e.g. a cluster that mixes real speech and echo).
        //    Fuzzy token overlap, since Whisper transcribes the two copies of
        //    the same words slightly differently.
        let beforeEcho = micAttributed.count
        micAttributed = micAttributed.filter { mic in
            !systemAttributed.contains { sys in
                let overlap = min(mic.end, sys.end) - max(mic.start, sys.start)
                guard overlap > 0.4 * max(0.1, mic.end - mic.start) else { return false }
                return isDuplicateText(mic.text, sys.text)
            }
        }
        if micAttributed.count != beforeEcho {
            Log.info("Echo guard dropped \(beforeEcho - micAttributed.count) duplicated mic segment(s)")
        }

        // 6. Interleave into one timeline and fold into speaker turns.
        var timeline = systemAttributed + micAttributed
        timeline.sort { $0.start < $1.start }
        var turns: [(speaker: String, text: String)] = []
        for segment in timeline {
            if var last = turns.last, last.speaker == segment.speaker {
                last.text += " " + segment.text
                turns[turns.count - 1] = last
            } else {
                turns.append((speaker: segment.speaker, text: segment.text))
            }
        }
        let text = turns.map { "**\($0.speaker):** \($0.text)" }.joined(separator: "\n\n")

        // 7. Samples come from each voice's own clean channel (echo clusters
        //    excluded — their "voice" is already sampled from the system side).
        var samples: [Diarizer.SpeakerSample] = []
        if let sampleClipsDir {
            samples = await Diarizer.exportSamples(
                from: channels.system, segments: systemSegments, to: sampleClipsDir)
            samples += await Diarizer.exportSamples(
                from: channels.mic,
                segments: micSegments.filter { !echoLabels.contains($0.speaker) },
                to: sampleClipsDir)
        }

        // 8. Catalogue upkeep, as in the single-channel path.
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd HH:mm"
        var speakerRecords: [(label: String, recordID: UUID)] = []
        for (label, embedding) in allEmbeddings {
            let displayLabel = displayNames[label] ?? label
            if let id = matchedIDs[label] {
                SpeakerCatalog.shared.touch(id: id)
                speakerRecords.append((label: displayLabel, recordID: id))
            } else if let clip = samples.first(where: { $0.speaker == displayLabel })?.url {
                if let id = SpeakerCatalog.shared.register(
                    context: "\(label) · meeting \(stamp.string(from: Date()))",
                    embedding: embedding,
                    sampleClip: clip) {
                    speakerRecords.append((label: displayLabel, recordID: id))
                }
            }
        }

        let speakerCount = Set(timeline.map(\.speaker)).count
        return Output(
            text: text, speakerCount: speakerCount,
            speakerSamples: samples, speakerRecords: speakerRecords)
    }

    /// Attributes whisper segments to the channel's diarized voices; segments
    /// overlapping no diarized speech inherit the previous speaker, or the
    /// channel's fallback label.
    static func attributed(
        whisper: [(start: Double, end: Double, text: String)],
        diarized: [Diarizer.SpeakerSegment],
        fallbackLabel: String
    ) -> [AttributedSegment] {
        var result: [AttributedSegment] = []
        var lastSpeaker: String?
        for segment in whisper {
            var overlaps: [String: Double] = [:]
            for speaker in diarized {
                let overlap = min(segment.end, speaker.end) - max(segment.start, speaker.start)
                if overlap > 0 { overlaps[speaker.speaker, default: 0] += overlap }
            }
            // Prefer the channel's first diarized voice over the generic
            // fallback so an opening pre-diarization segment doesn't get an
            // orphan label.
            let speaker = overlaps.max(by: { $0.value < $1.value })?.key
                ?? lastSpeaker ?? diarized.first?.speaker ?? fallbackLabel
            lastSpeaker = speaker
            result.append(AttributedSegment(
                start: segment.start, end: segment.end, text: segment.text, speaker: speaker))
        }
        return result
    }

    /// Fuzzy same-words check: containment or strong token overlap.
    static func isDuplicateText(_ a: String, _ b: String) -> Bool {
        let na = normalized(a), nb = normalized(b)
        guard !na.isEmpty, !nb.isEmpty else { return false }
        if na.contains(nb) || nb.contains(na) { return true }
        let ta = Set(na.split(separator: " ")), tb = Set(nb.split(separator: " "))
        guard ta.count >= 3, tb.count >= 3 else { return false }
        let intersection = ta.intersection(tb).count
        return Double(intersection) / Double(min(ta.count, tb.count)) >= 0.6
    }

    static func normalized(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func whisperRawSegments(
        audioURL: URL, locale: Locale, model: String
    ) async throws -> [(start: Double, end: Double, text: String)] {
        let pipeline = try await whisperPipeline(model: model)
        var options = DecodingOptions()
        options.task = .transcribe
        options.chunkingStrategy = .vad
        options.skipSpecialTokens = true
        if let language = locale.language.languageCode?.identifier {
            options.language = language
        }
        primeWithVocabulary(&options, pipeline: pipeline)
        let results = try await pipeline.transcribe(
            audioPath: audioURL.path, decodeOptions: options)
        let segments = results.flatMap(\.segments)
        let kept = segments.filter { !isLikelyHallucination($0) }
        if kept.count != segments.count {
            Log.info("Dropped \(segments.count - kept.count) low-confidence/hallucinated segment(s) from \(audioURL.lastPathComponent)")
        }
        return kept
            .map { (start: Double($0.start), end: Double($0.end),
                    text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.text.isEmpty }
            .sorted { $0.start < $1.start }
    }

    /// Biases Whisper's decoder toward the user dictionary (names, product
    /// and technology terms) via its priming-prompt mechanism.
    private static func primeWithVocabulary(_ options: inout DecodingOptions, pipeline: WhisperKit) {
        guard let prompt = Vocabulary.whisperPrompt(terms: Vocabulary.current().terms),
              let tokenizer = pipeline.tokenizer else { return }
        let tokens = tokenizer.encode(text: " " + prompt)
            .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
        guard !tokens.isEmpty else { return }
        options.promptTokens = tokens
        options.usePrefillPrompt = true
    }

    /// Whisper hallucinates stock phrases ("Jesus.", "Thank you.") over
    /// non-speech audio, and loops phrases when decoding degrades. Its own
    /// per-segment metadata flags both.
    static func isLikelyHallucination(_ segment: TranscriptionSegment) -> Bool {
        // Whisper's classic gate: probably-not-speech + unconfident decode.
        if segment.noSpeechProb > 0.6 && segment.avgLogprob < -1.0 { return true }
        // Deeply unconfident decode regardless of speech probability.
        if segment.avgLogprob < -1.8 { return true }
        // Repetition loop (compression ratio) — "Jesus. Jesus. Jesus."
        if segment.compressionRatio > 2.4 { return true }
        // Explicit check for one short phrase repeated over and over
        // ("Jesus. Jesus. Jesus.", "Thank you. Thank you. Thank you.").
        let words = normalized(segment.text).split(separator: " ")
        for phraseLength in 1...3 where words.count >= phraseLength * 3 {
            let phrase = Array(words.prefix(phraseLength))
            if words.count % phraseLength == 0,
               stride(from: 0, to: words.count, by: phraseLength).allSatisfy({ offset in
                   Array(words[offset..<offset + phraseLength]) == phrase
               }) {
                return true
            }
        }
        return false
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
            // CPU + Neural Engine only: the default mel stage uses the GPU,
            // which starves video rendering when the user is already on the
            // next call while this one transcribes.
            computeOptions: ModelComputeOptions(melCompute: .cpuAndNeuralEngine),
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
        audioURL: URL, locale: Locale, model: String, diarize: Bool,
        sampleClipsDir: URL?, voiceMatchThreshold: Double
    ) async throws -> Output {
        let pipeline = try await whisperPipeline(model: model)

        var options = DecodingOptions()
        options.task = .transcribe
        options.chunkingStrategy = .vad
        options.skipSpecialTokens = true
        if let language = locale.language.languageCode?.identifier {
            options.language = language
        }
        primeWithVocabulary(&options, pipeline: pipeline)

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
            let outcome = try await Diarizer.diarize(audioURL: audioURL)
            guard !outcome.segments.isEmpty else {
                return Output(text: plainText, speakerCount: nil)
            }

            // Match each voice against the speaker catalogue: recognised and
            // named voices appear by name; unrecognised ones stay "Speaker N".
            var displayNames: [String: String] = [:]
            var matchedIDs: [String: UUID] = [:]
            for (label, embedding) in outcome.meanEmbeddings {
                if let match = SpeakerCatalog.shared.bestMatch(
                    embedding: embedding, threshold: voiceMatchThreshold) {
                    matchedIDs[label] = match.id
                    if let name = match.name, !name.isEmpty {
                        displayNames[label] = name
                        Log.info("Recognised \(label) as \(name) (similarity \(String(format: "%.2f", match.similarity)))")
                    } else {
                        Log.info("\(label) matches an uncatalogued voice heard before (similarity \(String(format: "%.2f", match.similarity)))")
                    }
                }
            }
            let speakerSegments = outcome.segments.map { segment in
                displayNames[segment.speaker].map {
                    Diarizer.SpeakerSegment(speaker: $0, start: segment.start, end: segment.end)
                } ?? segment
            }
            let whisperSegments = results
                .flatMap(\.segments)
                .filter { !isLikelyHallucination($0) }
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

            // Catalogue upkeep: refresh matched voices, register new ones so
            // they show up in Settings > Speaker Identification for naming.
            let stamp = DateFormatter()
            stamp.dateFormat = "yyyy-MM-dd HH:mm"
            var speakerRecords: [(label: String, recordID: UUID)] = []
            for (label, embedding) in outcome.meanEmbeddings {
                let displayLabel = displayNames[label] ?? label
                if let id = matchedIDs[label] {
                    SpeakerCatalog.shared.touch(id: id)
                    speakerRecords.append((label: displayLabel, recordID: id))
                } else if let clip = samples.first(where: { $0.speaker == displayLabel })?.url {
                    if let id = SpeakerCatalog.shared.register(
                        context: "\(label) · meeting \(stamp.string(from: Date()))",
                        embedding: embedding,
                        sampleClip: clip) {
                        speakerRecords.append((label: displayLabel, recordID: id))
                    }
                }
            }
            return Output(
                text: attributed, speakerCount: speakerCount,
                speakerSamples: samples, speakerRecords: speakerRecords)
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
