import Foundation
import Testing

@testable import EarwigKit

/// The user dictionary: entry parsing, deterministic corrections, and the
/// Whisper priming prompt.
struct VocabularyTests {
    @Test func parsesTermsAndCorrectionPairs() {
        let parsed = Vocabulary.parse(entries: [
            "Orbit", "  ClearRoute  ", "Zurb -> Azure", "glenn -> Glyn", "", "  ",
        ])
        #expect(parsed.terms == ["Orbit", "ClearRoute", "Azure", "Glyn"])
        #expect(parsed.corrections.map(\.wrong) == ["Zurb", "glenn"])
        #expect(parsed.corrections.map(\.right) == ["Azure", "Glyn"])
    }

    @Test func correctionsAreWordBoundaryAndCaseInsensitive() {
        let corrections = [(wrong: "zurb", right: "Azure"), (wrong: "glenn", right: "Glyn")]
        let (fixed, count) = Vocabulary.applyCorrections(
            corrections,
            to: "so Glenn moved the ZURB estate, but glennish stays and zurban stays")
        #expect(fixed == "so Glyn moved the Azure estate, but glennish stays and zurban stays")
        #expect(count == 2)
    }

    @Test func correctionsEscapeRegexAndTemplateMetacharacters() {
        let corrections = [(wrong: "a.b (beta)", right: "A$B")]
        let (fixed, count) = Vocabulary.applyCorrections(
            corrections, to: "deploying a.b (beta) now; also axb stays")
        #expect(fixed == "deploying A$B now; also axb stays")
        #expect(count == 1)
    }

    @Test func whisperPromptIsCappedAndNilWhenEmpty() {
        #expect(Vocabulary.whisperPrompt(terms: []) == nil)
        let many = (1...60).map { "Term\($0)" }
        let prompt = Vocabulary.whisperPrompt(terms: many)!
        #expect(prompt.hasPrefix("Glossary: Term1, "))
        #expect(prompt.contains("Term40"))
        #expect(!prompt.contains("Term41"))
    }
}
