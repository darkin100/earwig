import AVFoundation
import Foundation

/// Records mic (AVAudioEngine) + system audio (CoreAudio process tap), merged to .m4a.
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

    /// `merged` is what the transcription pipeline consumes; caller owns `workDir` cleanup.
    struct Recording {
        let merged: URL
        let workDir: URL
    }

    private(set) var isRecording = false
    private(set) var startedAt: Date?

    private let engine = AVAudioEngine()
    private var micFile: AVAudioFile?
    private var micWriteError: Error?   // latched first mic-buffer write failure
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
        micWriteError = nil
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            do {
                try self.micFile?.write(from: buffer)
            } catch {
                // Latch the first failure instead of silently dropping every later buffer.
                if self.micWriteError == nil { self.micWriteError = error }
            }
        }
        engine.prepare()
        try engine.start()
    }

    /// Stops captures, writes merged m4a. Caller owns workDir cleanup.
    func stop(mergedTo destination: URL) async throws -> Recording {
        guard isRecording else { throw RecorderError.notRecording }
        isRecording = false

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        micFile = nil

        systemTap.stop()

        // Tap removed + engine stopped: no more buffers can arrive, so the latch is safe to
        // read. A truncated mic track still merges, so surface it rather than pass it as clean.
        if let micWriteError {
            Log.info("Microphone capture had write errors (\(micWriteError)); the mic track may be incomplete")
        }

        do {
            try await merge(to: destination)
        } catch {
            // workDir holds the only surviving copy — keep it for --merge recovery.
            Log.info("Merge failed; raw captures preserved in \(workDir.path) — recover with --merge")
            throw error
        }
        Log.info("Recording stopped, merged to \(destination.path)")
        return Recording(merged: destination, workDir: workDir)
    }

    private func merge(to destination: URL) async throws {
        _ = try await Recorder.merge(inputs: [micURL, systemURL], to: destination)
    }

    /// Mixes inputs into a single m4a. Returns count actually merged (skipped inputs are logged).
    @discardableResult
    static func merge(inputs: [URL], to destination: URL) async throws -> Int {
        let composition = AVMutableComposition()
        var added = 0
        for url in inputs {
            guard FileManager.default.fileExists(atPath: url.path) else {
                Log.info("merge: skipping missing input \(url.lastPathComponent)")
                continue
            }
            let asset = AVURLAsset(url: url)
            let assetTrack: AVAssetTrack?
            do {
                assetTrack = try await asset.loadTracks(withMediaType: .audio).first
            } catch {
                Log.info("merge: could not read audio track from \(url.lastPathComponent) (\(error)); skipping")
                continue
            }
            guard let assetTrack else {
                Log.info("merge: no audio track in \(url.lastPathComponent); skipping")
                continue
            }
            let duration = try await asset.load(.duration)
            guard duration.seconds > 0 else {
                Log.info("merge: \(url.lastPathComponent) has zero duration; skipping")
                continue
            }
            guard let track = composition.addMutableTrack(
                withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
            try track.insertTimeRange(
                CMTimeRange(start: .zero, duration: duration), of: assetTrack, at: .zero)
            added += 1
        }
        guard added > 0 else { throw RecorderError.exportFailed("no audio captured") }
        if added < inputs.count {
            Log.info("merge: only \(added) of \(inputs.count) input(s) merged into \(destination.lastPathComponent)")
        }

        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw RecorderError.exportFailed("could not create export session")
        }
        // Folder can be missing on first run or if moved mid-session.
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: destination)
        try await export.export(to: destination, as: .m4a)
        return added
    }

    var elapsed: TimeInterval {
        guard let startedAt else { return 0 }
        return Date().timeIntervalSince(startedAt)
    }
}
