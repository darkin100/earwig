import Foundation

/// Wraps a diarized speaker label so it can drive an `Identifiable`-based popover
/// in the meeting detail view. Carries a representative audio sample (the speaker's
/// longest turn) so the naming sheet can play their voice for identification.
struct SpeakerSelection: Identifiable {
    let label: String
    let audioURL: URL?
    let sampleStart: TimeInterval
    let sampleEnd: TimeInterval
    var id: String { label }
}
