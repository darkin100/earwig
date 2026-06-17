import Foundation

/// A per-speaker summary derived from a meeting's transcript turns, used to drive
/// the Speakers panel: who spoke, whether they're named yet, a representative snippet,
/// and a playable sample range (their longest turn).
struct SpeakerInfo: Identifiable, Hashable {
    let id = UUID()
    let label: String           // "Speaker 1" or "Cecile"
    let isNamed: Bool           // false when label is "Speaker N" / "Others"
    let snippet: String         // longest turn's text, truncated
    let sampleStart: TimeInterval
    let sampleEnd: TimeInterval
}
