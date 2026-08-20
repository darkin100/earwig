import Foundation
import Testing

@testable import EarwigKit

/// The user dictionary: entry parsing and deterministic corrections.
/// (Whisper priming was removed — it made the decoder drop real speech.)
struct VocabularyTests {
    @Test func parsesTermsAndCorrectionPairs() {
        let parsed = Vocabulary.parse(entries: [
            "Orbit", "  ClearRoute  ", "Zurb -> Azure", "glenn -> Glyn", "", "  ",
        ])
        // A correction pair's target stays out of `terms`: the pair is applied
        // deterministically, and glossary entries pull the repair model toward
        // them (it rewrote "GCP" to "Azure" when Azure was in the glossary).
        #expect(parsed.terms == ["Orbit", "ClearRoute"])
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
}
