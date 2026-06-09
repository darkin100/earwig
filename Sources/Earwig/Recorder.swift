import AVFoundation
import Foundation
import ScreenCaptureKit

/// Records two audio streams simultaneously:
///  - the microphone (your voice) via AVAudioEngine
///  - system audio (everyone else on the call) via ScreenCaptureKit
/// then merges them into a single .m4a file.
final class Recorder: NSObject, SCStreamOutput, SCStreamDelegate {
    enum RecorderError: Error, LocalizedError {
        case alreadyRecording
        case notRecording
        case noDisplay
        case exportFailed(String)

        var errorDescription: String? {
            switch self {
            case .alreadyRecording: return "Already recording"
            case .notRecording: return "Not recording"
            case .noDisplay: return "No display found for system audio capture"
            case .exportFailed(let why): return "Audio merge failed: \(why)"
            }
        }
    }

    private(set) var isRecording = false
    private(set) var startedAt: Date?

    private let engine = AVAudioEngine()
    private var micFile: AVAudioFile?
    private var systemFile: AVAudioFile?
    private var stream: SCStream?
    private let sampleQueue = DispatchQueue(label: "io.darkin.earwig.audio")

    private var workDir: URL!
    private var micURL: URL { workDir.appendingPathComponent("mic.caf") }
    private var systemURL: URL { workDir.appendingPathComponent("system.caf") }

    /// Starts both captures. Throws if mic or screen-capture permission is missing.
    func start() async throws {
        guard !isRecording else { throw RecorderError.alreadyRecording }

        workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("earwig-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

        try await startSystemCapture()
        try startMicCapture()

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

    private func startSystemCapture() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first else { throw RecorderError.noDisplay }

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48000
        config.channelCount = 2
        // We only consume the audio output; keep video work minimal.
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
        try await stream.startCapture()
        self.stream = stream
    }

    // MARK: SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid else { return }
        guard let pcm = sampleBuffer.toPCMBuffer() else { return }
        do {
            if systemFile == nil {
                systemFile = try AVAudioFile(forWriting: systemURL, settings: pcm.format.settings)
            }
            try systemFile?.write(from: pcm)
        } catch {
            Log.info("system audio write error: \(error)")
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Log.info("SCStream stopped with error: \(error)")
    }

    /// Stops both captures and returns the merged m4a written to `destination`.
    func stop(mergedTo destination: URL) async throws -> URL {
        guard isRecording else { throw RecorderError.notRecording }
        isRecording = false

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        micFile = nil

        if let stream {
            try? await stream.stopCapture()
        }
        stream = nil
        sampleQueue.sync { } // drain in-flight sample writes
        systemFile = nil

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

extension CMSampleBuffer {
    /// Converts an audio CMSampleBuffer from ScreenCaptureKit into an AVAudioPCMBuffer.
    func toPCMBuffer() -> AVAudioPCMBuffer? {
        guard let description = CMSampleBufferGetFormatDescription(self) else { return nil }
        let format = AVAudioFormat(cmAudioFormatDescription: description)
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(self))
        guard frames > 0,
              let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        pcm.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            self, at: 0, frameCount: Int32(frames), into: pcm.mutableAudioBufferList)
        return status == noErr ? pcm : nil
    }
}
