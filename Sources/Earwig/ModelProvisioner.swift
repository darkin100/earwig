import Foundation

/// Downloads and warms Whisper + diarization models during onboarding.
/// Progress is two sequential stages: Whisper (real progress) then diarization (no API → fixed step).
/// Summary LLM is not provisioned here — that's optional and engine-specific.
enum ModelProvisioner {
    static let whisperWeight = 0.85  // share of the bar; ~625 MB download
    static var diarizationWeight: Double { 1 - whisperWeight }

    static func combinedProgress(whisperFraction: Double, diarizationDone: Bool) -> Double {
        let w = clamp(whisperFraction) * whisperWeight
        let d = diarizationDone ? diarizationWeight : 0
        return min(1, w + d)
    }

    private static func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }

    /// Downloads + warms Whisper then diarization. Throws so onboarding can show Retry.
    @MainActor
    static func downloadAndWarm(onProgress: @escaping @MainActor (Double) -> Void) async throws {
        onProgress(0)
        try await Transcriber.prewarm { progress in
            let f = progress.fractionCompleted
            Task { @MainActor in
                onProgress(combinedProgress(whisperFraction: f, diarizationDone: false))
            }
        }
        onProgress(combinedProgress(whisperFraction: 1, diarizationDone: false))

        try await Diarizer.prewarm()
        onProgress(1.0)
    }
}
