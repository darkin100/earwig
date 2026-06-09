import AVFoundation
import Foundation

/// Records two audio streams simultaneously:
///  - the microphone (your voice) via AVAudioEngine
///  - system audio (everyone else on the call) via a CoreAudio process tap
/// then merges them into a single .m4a file.
final class Recorder {
    enum RecorderError: Error, LocalizedError {
        case alreadyRecording
        case notRecording
        case exportFailed(String)

        var errorDescription: String? {
            switch self {
            case .alreadyRecording: return "Already recording"
            case .notRecording: return "Not recording"
            case .exportFailed(let why): return "Audio merge failed: \(why)"
            }
        }
    }

    private(set) var isRecording = false
    private(set) var startedAt: Date?

    private let engine = AVAudioEngine()
    private var micFile: AVAudioFile?
    private let systemTap = SystemAudioTap()

    private var workDir: URL!
    private var micURL: URL { workDir.appendingPathComponent("mic.caf") }
    private var systemURL: URL { workDir.appendingPathComponent("system.caf") }

    /// Starts both captures. Throws if microphone or system-audio permission is missing.
    func start() async throws {
        guard !isRecording else { throw RecorderError.alreadyRecording }

        workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("earwig-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

        // System audio first: the tap creation triggers the (one-time)
        // "System Audio Recording Only" permission prompt.
        try systemTap.start(writingTo: systemURL)
        do {
            try startMicCapture()
        } catch {
            systemTap.stop()
            throw error
        }

        isRecording = true
        startedAt = Date()
        Log.info("Recording started -> \(workDir.path)")
    }

    private func startMicCapture() throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let file = try AVAudioFile(forWriting: micURL, settings: format.settings)
        micFile = file
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            try? self?.micFile?.write(from: buffer)
        }
        engine.prepare()
        try engine.start()
    }

    /// Stops both captures and returns the merged m4a written to `destination`.
    func stop(mergedTo destination: URL) async throws -> URL {
        guard isRecording else { throw RecorderError.notRecording }
        isRecording = false

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        micFile = nil

        systemTap.stop()

        try await merge(to: destination)
        Log.info("Recording stopped, merged to \(destination.path)")
        return destination
    }

    private func merge(to destination: URL) async throws {
        let composition = AVMutableComposition()
        var added = 0
        for url in [micURL, systemURL] where FileManager.default.fileExists(atPath: url.path) {
            let asset = AVURLAsset(url: url)
            guard let assetTrack = try? await asset.loadTracks(withMediaType: .audio).first else { continue }
            let duration = try await asset.load(.duration)
            guard duration.seconds > 0 else { continue }
            guard let track = composition.addMutableTrack(
                withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
            try track.insertTimeRange(
                CMTimeRange(start: .zero, duration: duration), of: assetTrack, at: .zero)
            added += 1
        }
        guard added > 0 else { throw RecorderError.exportFailed("no audio captured") }

        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw RecorderError.exportFailed("could not create export session")
        }
        try? FileManager.default.removeItem(at: destination)
        try await export.export(to: destination, as: .m4a)
    }

    var elapsed: TimeInterval {
        guard let startedAt else { return 0 }
        return Date().timeIntervalSince(startedAt)
    }
}
