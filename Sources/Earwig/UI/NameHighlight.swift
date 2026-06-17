import SwiftUI

/// Highlights people's names in summary text with accent colour + bold (no underline — that read
/// too harshly). Only highlights actual people: the meeting's known speaker labels and any
/// "Speaker N". It does NOT guess at leading "Name:" prefixes, so non-people like "Workflow" or a
/// bolded phrase are left alone. Bolding uses `inlinePresentationIntent` so it inherits the
/// surrounding text size.
enum NameHighlight {
    /// Compiled once at program start; matches "Speaker 1", "Speaker 2", etc.
    private static let speakerRegex = try? NSRegularExpression(pattern: "Speaker \\d+")

    static func attributed(_ text: String, names: [String]) -> AttributedString {
        var result = AttributedString(text)
        let ns = text as NSString

        // Only the meeting's real speakers count as people.
        var targets = Set(names
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count >= 2 })

        // Unnamed-but-real speakers ("Speaker 1", "Speaker 2", ...).
        if let rx = speakerRegex {
            for m in rx.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                targets.insert(ns.substring(with: m.range))
            }
        }

        // Longer names first so a longer match isn't pre-empted by a shorter substring.
        for name in targets.sorted(by: { $0.count > $1.count }) {
            apply(name, to: &result, source: text)
        }
        return result
    }

    private static func apply(_ name: String, to result: inout AttributedString, source: String) {
        let lower = source.lowercased()
        let needle = name.lowercased()
        var from = lower.startIndex
        while let r = lower.range(of: needle, range: from ..< lower.endIndex) {
            let beforeOK = r.lowerBound == lower.startIndex || !lower[lower.index(before: r.lowerBound)].isLetter
            let afterOK = r.upperBound == lower.endIndex || !lower[r.upperBound].isLetter
            if beforeOK, afterOK,
               let lo = AttributedString.Index(r.lowerBound, within: result),
               let hi = AttributedString.Index(r.upperBound, within: result) {
                result[lo ..< hi].foregroundColor = Theme.accent
                result[lo ..< hi].inlinePresentationIntent = .stronglyEmphasized
            }
            from = r.upperBound
        }
    }
}
