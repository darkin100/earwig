import Foundation

/// The user dictionary: names, technologies, and org-specific terms that
/// speech-to-text routinely gets wrong.
///
/// Entries in config's `vocabulary` are either a canonical term ("Orbit",
/// "Glyn Darkin") or an explicit correction pair ("Zurb -> Azure"). Names
/// from the speaker catalogue are always included automatically.
///
/// The two entry kinds drive two separate stages and do not overlap:
/// correction pairs are applied as deterministic word-boundary replacements,
/// while canonical terms (plus catalogue names) become the on-device repair
/// model's glossary. A pair's target is never added to that glossary — the
/// deterministic pass already handles it, and every extra glossary term is
/// something the repair model may pull unrelated words toward.
///
/// Whisper decoder priming was removed — see the note in Transcriber.swift:
/// prompts make WhisperKit drop real speech.
enum Vocabulary {
    struct Current {
        let terms: [String]
        let corrections: [(wrong: String, right: String)]
    }

    static func current() -> Current {
        var current = parse(entries: Config.load().vocabulary ?? [])
        // The speaker catalogue is a dictionary of names we already know.
        var terms = current.terms
        for record in SpeakerCatalog.shared.all() {
            if let name = record.name, !name.isEmpty, !terms.contains(name) {
                terms.append(name)
            }
        }
        current = Current(terms: terms, corrections: current.corrections)
        return current
    }

    /// Pure parsing of dictionary entries — a line is either a canonical term
    /// or a "wrong -> right" correction pair.
    static func parse(entries: [String]) -> Current {
        var terms: [String] = []
        var corrections: [(wrong: String, right: String)] = []
        for raw in entries {
            let parts = raw.components(separatedBy: "->")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty {
                // Deliberately NOT added to `terms`: a correction pair is
                // already applied deterministically, and putting its target in
                // the repair model's glossary makes that model pull unrelated
                // words toward it — "GCP"/"GCVE" were rewritten to "Azure"
                // purely because "Zurb -> Azure" put Azure in the glossary.
                corrections.append((wrong: parts[0], right: parts[1]))
            } else {
                let term = raw.trimmingCharacters(in: .whitespaces)
                if !term.isEmpty, !terms.contains(term) { terms.append(term) }
            }
        }
        return Current(terms: terms, corrections: corrections)
    }

    /// Case-insensitive word-boundary replacement of known mis-hearings.
    static func applyCorrections(
        _ corrections: [(wrong: String, right: String)], to text: String
    ) -> (text: String, count: Int) {
        var result = text
        var total = 0
        for (wrong, right) in corrections {
            // Lookarounds, not \b: terms can start or end with non-word
            // characters ("a.b (beta)"), where \b never matches.
            let pattern = "(?<!\\w)" + NSRegularExpression.escapedPattern(for: wrong) + "(?!\\w)"
            guard let regex = try? NSRegularExpression(
                pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            let matches = regex.numberOfMatches(in: result, range: range)
            if matches > 0 {
                result = regex.stringByReplacingMatches(
                    in: result, range: range,
                    withTemplate: NSRegularExpression.escapedTemplate(for: right))
                total += matches
            }
        }
        return (result, total)
    }
}
