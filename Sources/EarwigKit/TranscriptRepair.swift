import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Context-aware repair of speech-to-text mis-recognitions using Apple's
/// on-device Foundation Model (Apple Intelligence). Fixes only what context
/// makes obvious — "the servility" -> "the observability", misheard names —
/// and is content-preserving by construction: any chunk the model returns
/// structurally altered is discarded in favour of the original.
enum TranscriptRepair {
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    /// Returns the repaired transcript, or nil when unavailable or nothing
    /// needed changing.
    static func repair(transcript: String, speakerNames: [String]) async -> String? {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *) else { return nil }
        guard case .available = SystemLanguageModel.default.availability else {
            Log.info("Transcript repair skipped — Apple Intelligence unavailable")
            return nil
        }

        // Chunk by turns to stay well inside the on-device context window.
        let turns = transcript.components(separatedBy: "\n\n")
        var chunks: [[String]] = [[]]
        var size = 0
        for turn in turns {
            if size + turn.count > 2500, !chunks[chunks.count - 1].isEmpty {
                chunks.append([])
                size = 0
            }
            chunks[chunks.count - 1].append(turn)
            size += turn.count
        }

        let names = speakerNames.filter { !$0.hasPrefix("Speaker ") }
        let vocabulary = Vocabulary.current().terms.filter { !names.contains($0) }
        let glossaryLine = vocabulary.isEmpty ? "" : """

        - Domain glossary — when the audio plausibly meant one of these terms, use this exact spelling: \(vocabulary.prefix(40).joined(separator: ", ")).
        """
        let instructions = """
        You repair speech-to-text errors in a meeting transcript. Rules:
        - Fix only obvious mis-recognitions where the surrounding context makes the intended word clear. Examples: "the servility" -> "the observability" in a discussion of platform capabilities; "in the Zurb" -> "in Azure" when discussing cloud hosting.
        - When a name is misheard or misspelled, correct it to exactly match one of the participants: \(names.isEmpty ? "unknown" : names.joined(separator: ", ")). For example "glenn" or "Glen" -> "Glyn" if Glyn is a participant. Never invent names not in the list.\(glossaryLine)
        - Preserve everything else exactly as written: the same sentences, the same order, the same wording, and the same "**Name:**" speaker markers. Never summarise, rephrase, reorder, add, or remove content. Keep hesitations and informal speech as they are.
        - If nothing needs fixing, output the text unchanged.
        - Output only the corrected transcript text, nothing else.
        """

        var repairedChunks: [String] = []
        var repairedAny = false
        for chunk in chunks {
            let original = chunk.joined(separator: "\n\n")
            guard original.contains("**") else {
                repairedChunks.append(original)
                continue
            }
            do {
                // Fresh session per chunk keeps the model's context bounded
                // regardless of meeting length.
                let session = LanguageModelSession(instructions: instructions)
                var options = GenerationOptions()
                options.temperature = 0.1
                let response = try await session.respond(to: original, options: options)
                let candidate = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if isSafeRepair(original: original, candidate: candidate) {
                    if candidate != original { repairedAny = true }
                    repairedChunks.append(candidate)
                } else {
                    repairedChunks.append(original)
                }
            } catch {
                Log.info("Transcript repair chunk failed (\(error)); keeping original")
                repairedChunks.append(original)
            }
        }
        guard repairedAny else { return nil }
        Log.info("Transcript repair applied (on-device model)")
        return repairedChunks.joined(separator: "\n\n")
        #else
        return nil
        #endif
    }

    /// A repair is only accepted when the chunk comes back structurally
    /// intact: same speaker-marker count, similar length.
    static func isSafeRepair(original: String, candidate: String) -> Bool {
        guard !candidate.isEmpty else { return false }
        let ratio = Double(candidate.count) / Double(max(1, original.count))
        guard ratio > 0.7, ratio < 1.3 else { return false }
        let markerCount = { (s: String) in s.components(separatedBy: "**").count }
        guard markerCount(original) == markerCount(candidate) else { return false }
        // Markdown headings must survive verbatim (the model once renamed
        // "## Transcript" to "## Corrected Transcript").
        let headings = { (s: String) in
            s.split(separator: "\n").filter { $0.hasPrefix("#") }
        }
        return headings(original) == headings(candidate)
    }

    /// Speaker names as they appear in a turn-formatted transcript.
    static func speakerNames(in transcript: String) -> [String] {
        var names: [String] = []
        transcript.enumerateSubstrings(in: transcript.startIndex..<transcript.endIndex,
                                       options: .byLines) { line, _, _, _ in
            if let line, line.hasPrefix("**"),
               let end = line.range(of: ":**") {
                let name = String(line.dropFirst(2)[..<end.lowerBound])
                if !names.contains(name) { names.append(name) }
            }
        }
        return names
    }
}
