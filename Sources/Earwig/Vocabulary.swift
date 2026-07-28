import Foundation

/// The user dictionary: names, technologies, and org-specific terms that
/// speech-to-text routinely gets wrong.
///
/// Entries in config's `vocabulary` are either a canonical term ("Orbit",
/// "Glyn Darkin") or an explicit correction pair ("Zurb -> Azure"). Names
/// from the speaker catalogue are always included automatically. The terms
/// feed three stages: Whisper's priming prompt (hear it right), determinis-
/// tic word-boundary corrections (fix known offenders), and the on-device
/// repair model's glossary (snap context repairs to exact spellings).
enum Vocabulary {
    struct Current {
        let terms: [String]
        let corrections: [(wrong: String, right: String)]
    }

    static func current() -> Current {
        let config = Config.load()
        var terms: [String] = []
        var corrections: [(wrong: String, right: String)] = []
        for raw in config.vocabulary ?? [] {
            let parts = raw.components(separatedBy: "->")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty {
                corrections.append((wrong: parts[0], right: parts[1]))
                if !terms.contains(parts[1]) { terms.append(parts[1]) }
            } else {
                let term = raw.trimmingCharacters(in: .whitespaces)
                if !term.isEmpty, !terms.contains(term) { terms.append(term) }
            }
        }
        // The speaker catalogue is a dictionary of names we already know.
        for record in SpeakerCatalog.shared.all() {
            if let name = record.name, !name.isEmpty, !terms.contains(name) {
                terms.append(name)
            }
        }
        return Current(terms: terms, corrections: corrections)
    }

    /// Whisper priming text — biases recognition toward the glossary.
    static func whisperPrompt(terms: [String]) -> String? {
        guard !terms.isEmpty else { return nil }
        return "Glossary: " + terms.prefix(40).joined(separator: ", ") + "."
    }

    /// Case-insensitive word-boundary replacement of known mis-hearings.
    static func applyCorrections(
        _ corrections: [(wrong: String, right: String)], to text: String
    ) -> (text: String, count: Int) {
        var result = text
        var total = 0
        for (wrong, right) in corrections {
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: wrong) + "\\b"
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
