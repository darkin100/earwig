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

        let chunks = pieces(of: transcript)

        let names = speakerNames.filter { !$0.hasPrefix("Speaker ") }
        let vocabulary = Vocabulary.current().terms.filter { !names.contains($0) }
        let glossaryLine = vocabulary.isEmpty ? "" : """

        - Domain glossary — when the audio plausibly meant one of these terms, use this exact spelling: \(vocabulary.prefix(24).joined(separator: ", ")).
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
        for original in chunks {
            guard original.contains(where: { !$0.isWhitespace }) else {
                repairedChunks.append(original)
                continue
            }
            let candidate = await repairPiece(original, instructions: instructions, depth: 0)
            if let candidate {
                if candidate != original { repairedAny = true }
                repairedChunks.append(candidate)
            } else {
                repairedChunks.append(original)
            }
        }
        guard repairedAny else { return nil }
        let result = repairedChunks.joined()
        // Whatever the model did to individual pieces, rejoining them must
        // not change the transcript's shape. Cheap insurance against a
        // chunking bug quietly reflowing the meeting.
        let turnCount = { (text: String) in text.components(separatedBy: "\n\n").count }
        guard turnCount(result) == turnCount(transcript) else {
            Log.info("Transcript repair changed the turn structure (\(turnCount(transcript)) -> \(turnCount(result))); keeping the original transcript")
            return nil
        }
        Log.info("Transcript repair applied (on-device model)")
        return result
        #else
        return nil
        #endif
    }

    /// Repairs one piece of transcript, returning nil to mean "keep the
    /// original".
    ///
    /// On a context-window overflow the piece is split and each half repaired
    /// instead. The old code caught that error and kept the original, so a
    /// stretch of the meeting silently went unrepaired — and it overflowed
    /// routinely, because `maximumResponseTokens` was left unset and the
    /// framework then reserves a large default response allocation on top of
    /// the instructions and prompt.
    private static func repairPiece(
        _ text: String, instructions: String, depth: Int
    ) async -> String? {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *) else { return nil }
        do {
            // Fresh session per piece keeps the model's context bounded
            // regardless of meeting length.
            let session = LanguageModelSession(instructions: instructions)
            var options = GenerationOptions()
            options.temperature = 0.1
            // The response is a rewrite of the input, so reserve roughly the
            // input's own size plus headroom rather than the default.
            options.maximumResponseTokens = estimatedTokens(text) * 3 / 2 + 128
            // The piece's own leading/trailing whitespace carries the turn
            // separators, and the model answers trimmed — restore the
            // envelope or turns silently merge when the pieces rejoin.
            let (leading, core, trailing) = whitespaceEnvelope(text)
            let response = try await session.respond(to: core, options: options)
            let candidate = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isSafeRepair(original: core, candidate: candidate) else { return nil }
            return leading + candidate + trailing
        } catch let error as LanguageModelSession.GenerationError {
            if case .exceededContextWindowSize = error, depth < 3 {
                let halves = pieces(of: text, budget: max(400, text.count / 2))
                if halves.count > 1 {
                    Log.info("Transcript repair piece exceeded the context window; splitting into \(halves.count) and retrying")
                    var rebuilt = ""
                    for half in halves {
                        rebuilt += await repairPiece(
                            half, instructions: instructions, depth: depth + 1) ?? half
                    }
                    return rebuilt
                }
            }
            Log.info("Transcript repair piece failed (\(error)); keeping original")
            return nil
        } catch {
            Log.info("Transcript repair piece failed (\(error)); keeping original")
            return nil
        }
        #else
        return nil
        #endif
    }

    /// Splits a piece into its leading whitespace, trimmed core, and trailing
    /// whitespace, such that `leading + core + trailing` is the original.
    static func whitespaceEnvelope(_ text: String) -> (leading: String, core: String, trailing: String) {
        let leadingCount = text.prefix(while: { $0.isWhitespace }).count
        guard leadingCount < text.count else { return (text, "", "") }
        let trailingCount = text.reversed().prefix(while: { $0.isWhitespace }).count
        return (String(text.prefix(leadingCount)),
                String(text.dropFirst(leadingCount).dropLast(trailingCount)),
                String(text.suffix(trailingCount)))
    }

    /// Rough token count for budgeting. Meeting transcripts tokenize denser
    /// than prose (disfluencies, names, `**Speaker:**` markers), so this
    /// deliberately over-estimates.
    static func estimatedTokens(_ text: String) -> Int { max(16, text.count / 3) }

    /// Splits a transcript into pieces small enough for the on-device model's
    /// context window.
    ///
    /// Pieces preserve the source exactly — `pieces(of: t).joined() == t` —
    /// so rejoining can never lose or reflow content. Turn boundaries are
    /// preferred; a single turn longer than the budget is split at sentence
    /// boundaries rather than sent whole, which the old chunker did (it only
    /// ever started a *new* chunk, so one long monologue went to the model
    /// intact however big it was).
    static func pieces(of transcript: String, budget: Int = 2000) -> [String] {
        let units = splitKeepingSeparator(transcript, separator: "\n\n")
            .flatMap { $0.count > budget ? sentenceUnits($0, budget: budget) : [$0] }
        var result: [String] = []
        var current = ""
        for unit in units {
            if !current.isEmpty, current.count + unit.count > budget {
                result.append(current)
                current = ""
            }
            current += unit
        }
        if !current.isEmpty { result.append(current) }
        return result.isEmpty ? [transcript] : result
    }

    /// Splits on `separator`, keeping it attached to the preceding piece so
    /// the parts rejoin byte-for-byte.
    private static func splitKeepingSeparator(_ text: String, separator: String) -> [String] {
        var result: [String] = []
        var rest = Substring(text)
        while let range = rest.range(of: separator) {
            result.append(String(rest[rest.startIndex..<range.upperBound]))
            rest = rest[range.upperBound...]
        }
        if !rest.isEmpty { result.append(String(rest)) }
        return result
    }

    /// Breaks an over-long turn at sentence ends, hard-splitting anything
    /// that still doesn't fit (one unpunctuated ramble).
    private static func sentenceUnits(_ text: String, budget: Int) -> [String] {
        var sentences: [String] = []
        var current = ""
        let characters = Array(text)
        var index = 0
        while index < characters.count {
            current.append(characters[index])
            if ".?!".contains(characters[index]),
               index + 1 < characters.count, characters[index + 1] == " " {
                current.append(characters[index + 1])
                sentences.append(current)
                current = ""
                index += 2
                continue
            }
            index += 1
        }
        if !current.isEmpty { sentences.append(current) }

        var units: [String] = []
        var packed = ""
        for sentence in sentences {
            if !packed.isEmpty, packed.count + sentence.count > budget {
                units.append(packed)
                packed = ""
            }
            packed += sentence
        }
        if !packed.isEmpty { units.append(packed) }
        return units.flatMap { $0.count > budget ? hardSplit($0, budget: budget) : [$0] }
    }

    private static func hardSplit(_ text: String, budget: Int) -> [String] {
        var result: [String] = []
        var rest = Substring(text)
        while rest.count > budget {
            let cut = rest.index(rest.startIndex, offsetBy: budget)
            result.append(String(rest[rest.startIndex..<cut]))
            rest = rest[cut...]
        }
        if !rest.isEmpty { result.append(String(rest)) }
        return result
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
