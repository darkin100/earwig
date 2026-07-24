import FluidAudio
import Foundation

/// Speaker diarization — "who spoke when" — via FluidAudio's offline pipeline
/// (pyannote segmentation + WeSpeaker embeddings, CoreML, on-device).
/// Produces anonymous speaker labels ("Speaker 1", "Speaker 2", ...) numbered
/// by order of first appearance.
enum Diarizer {
    struct SpeakerSegment {
        let speaker: String
        let start: Double
        let end: Double
    }

    // Models load once per app run; the transcription pipeline is serialized
    // so a single cached manager is safe.
    private static var manager: OfflineDiarizerManager?

    static func diarize(audioURL: URL) async throws -> [SpeakerSegment] {
        let mgr: OfflineDiarizerManager
        if let cached = manager {
            mgr = cached
        } else {
            let modelsDir = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Earwig/Models/Diarizer", isDirectory: true)
            try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)

            let new = OfflineDiarizerManager(config: .default)
            Log.info("Preparing diarization models (first run downloads them)...")
            try await new.prepareModels(directory: modelsDir)
            Log.info("Diarization models ready")
            manager = new
            mgr = new
        }

        let result = try await mgr.process(audioURL)

        // Renumber FluidAudio's speaker IDs by order of first appearance.
        var order: [String: Int] = [:]
        var segments: [SpeakerSegment] = []
        for segment in result.segments.sorted(by: { $0.startTimeSeconds < $1.startTimeSeconds }) {
            if order[segment.speakerId] == nil {
                order[segment.speakerId] = order.count + 1
            }
            segments.append(SpeakerSegment(
                speaker: "Speaker \(order[segment.speakerId]!)",
                start: Double(segment.startTimeSeconds),
                end: Double(segment.endTimeSeconds)
            ))
        }
        Log.info("Diarization found \(order.count) speaker(s) across \(segments.count) segments")
        return segments
    }
}
