import AudioToolbox
import AVFoundation
import CoreAudio
import EarwigObjC
import Foundation

/// Runs `body`, converting a raised Objective-C exception into a Swift error.
/// AVFoundation reports some invalid-argument cases by raising, which Swift
/// cannot catch — an uncaught one aborts the process.
func withObjCExceptionCatching(_ body: () -> Void) throws {
    var raised: NSError?
    if !EarwigCatchException(body, &raised) {
        throw raised ?? Recorder.RecorderError.micUnavailable("audio engine raised an exception")
    }
}

/// Records two audio streams simultaneously:
///  - the microphone (your voice) via AVAudioEngine
///  - system audio (everyone else on the call) via a CoreAudio process tap
/// then merges them into a single .m4a file.
final class Recorder {
    enum RecorderError: Error, LocalizedError {
        case alreadyRecording
        case notRecording
        case exportFailed(String)
        case micUnavailable(String)

        var errorDescription: String? {
            switch self {
            case .alreadyRecording: return "Already recording"
            case .notRecording: return "Not recording"
            case .exportFailed(let why): return "Audio merge failed: \(why)"
            case .micUnavailable(let why): return "Microphone capture unavailable: \(why)"
            }
        }
    }

    private(set) var isRecording = false
    private(set) var startedAt: Date?

    /// The raw per-channel captures from the most recent recording, kept for
    /// two-channel processing. `micOffset` is how many seconds after the
    /// system channel the microphone channel began.
    struct ChannelFiles {
        let mic: URL
        let system: URL
        let directory: URL
        let micOffset: TimeInterval
    }
    private(set) var lastChannels: ChannelFiles?
    private var micStartDate: Date?

    // Built per recording, not once per app run: an AVAudioEngine resolves the
    // input hardware format when it is created, and that resolution goes stale
    // when the audio device changes underneath it — which happens constantly
    // with Bluetooth headsets (a call grabs the mic, the headset switches from
    // A2DP to hands-free and republishes itself at a new rate). A stale engine
    // installs taps against a format the hardware no longer has.
    private var engine: AVAudioEngine?
    private var micFile: AVAudioFile?
    private let systemTap = SystemAudioTap()

    // A headset mid-profile-switch rejects the tap; it settles within about a
    // second, so a couple of quick retries recover the recording.
    private static let micAttempts = 3
    private static let micRetryDelay: TimeInterval = 0.7

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
            try await startMicCapture()
        } catch {
            systemTap.stop()
            throw error
        }

        isRecording = true
        startedAt = Date()
        Log.info("Recording started -> \(workDir.path)")
    }

    /// Attaches the microphone tap, retrying while a switching input device
    /// settles, then falling back to the built-in mic. Never raises: a start
    /// that cannot succeed throws so the caller can report it.
    private func startMicCapture() async throws {
        var lastError: Error?
        for attempt in 1...Self.micAttempts {
            do {
                try attachMicTap(deviceID: nil)
                return
            } catch {
                lastError = error
                teardownEngine()
                if attempt < Self.micAttempts {
                    Log.info("Mic capture attempt \(attempt) failed (\(error.localizedDescription)); retrying")
                    try? await Task.sleep(nanoseconds: UInt64(Self.micRetryDelay * 1_000_000_000))
                }
            }
        }

        // Last resort: the selected input is unusable (a headset stuck
        // mid-switch, or one that disappeared). The built-in mic still
        // captures the local speaker — a degraded recording beats none.
        if let builtIn = Self.builtInInputDevice() {
            Log.info("Input device unusable after \(Self.micAttempts) attempts — falling back to the built-in microphone")
            do {
                try attachMicTap(deviceID: builtIn)
                return
            } catch {
                lastError = error
                teardownEngine()
            }
        }
        throw lastError ?? RecorderError.micUnavailable("no usable input device")
    }

    /// Builds a fresh engine, validates the input format, and installs the tap.
    /// `deviceID` pins a specific input device (the fallback path); nil uses
    /// the system default.
    private func attachMicTap(deviceID: AudioDeviceID?) throws {
        let engine = AVAudioEngine()
        self.engine = engine
        let input = engine.inputNode

        if let deviceID {
            guard let unit = input.audioUnit else {
                throw RecorderError.micUnavailable("input node has no audio unit")
            }
            var device = deviceID
            let status = AudioUnitSetProperty(
                unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                &device, UInt32(MemoryLayout<AudioDeviceID>.size))
            guard status == noErr else {
                throw RecorderError.micUnavailable("could not select input device (status \(status))")
            }
        }

        let format = input.outputFormat(forBus: 0)
        guard Self.isUsableInputFormat(
            sampleRate: format.sampleRate, channelCount: format.channelCount) else {
            throw RecorderError.micUnavailable(
                "input format not ready (\(Int(format.sampleRate))Hz, \(format.channelCount)ch)")
        }

        let file = try AVAudioFile(forWriting: micURL, settings: format.settings)
        micFile = file

        // installTap re-validates the format against the node's *current*
        // hardware format and raises an Objective-C exception on mismatch —
        // the hardware can change in the moment between the read above and
        // this call, so it goes through the catching shim rather than
        // aborting the process.
        try withObjCExceptionCatching {
            input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
                try? self?.micFile?.write(from: buffer)
            }
        }

        engine.prepare()
        try engine.start()
        micStartDate = Date()
    }

    /// Releases the engine and its tap. Safe to call on a partially built one.
    private func teardownEngine() {
        guard let engine else { return }
        try? withObjCExceptionCatching {
            engine.inputNode.removeTap(onBus: 0)
        }
        if engine.isRunning { engine.stop() }
        self.engine = nil
        micFile = nil
    }

    /// A format the engine can actually record with. Zero values show up while
    /// an input device is being republished, and installing a tap with one is
    /// rejected outright.
    static func isUsableInputFormat(sampleRate: Double, channelCount: AVAudioChannelCount) -> Bool {
        sampleRate > 0 && channelCount > 0
    }

    /// Stops both captures and returns the merged m4a written to `destination`.
    func stop(mergedTo destination: URL) async throws -> URL {
        guard isRecording else { throw RecorderError.notRecording }
        isRecording = false

        teardownEngine()

        let systemStartDate = systemTap.fileStartDate
        systemTap.stop()

        var micOffset: TimeInterval = 0
        if let micStartDate, let systemStartDate {
            micOffset = max(0, micStartDate.timeIntervalSince(systemStartDate))
        }
        lastChannels = ChannelFiles(
            mic: micURL, system: systemURL, directory: workDir, micOffset: micOffset)

        try await merge(to: destination)
        Log.info("Recording stopped, merged to \(destination.path)")
        return destination
    }

    private func merge(to destination: URL) async throws {
        try await Recorder.merge(inputs: [micURL, systemURL], to: destination)
    }

    /// Mixes any number of audio files into a single m4a.
    static func merge(inputs: [URL], to destination: URL) async throws {
        let composition = AVMutableComposition()
        var added = 0
        for url in inputs where FileManager.default.fileExists(atPath: url.path) {
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

    // MARK: helpers

    /// The built-in microphone, used as a last-resort fallback when the
    /// selected input device won't start.
    private static func builtInInputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr,
            size > 0 else { return nil }
        var devices = [AudioDeviceID](
            repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices) == noErr
        else { return nil }

        for device in devices where hasInputChannels(device) {
            var transport = UInt32(0)
            var transportSize = UInt32(MemoryLayout<UInt32>.size)
            var transportAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyTransportType,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            guard AudioObjectGetPropertyData(
                device, &transportAddress, 0, nil, &transportSize, &transport) == noErr
            else { continue }
            if transport == kAudioDeviceTransportTypeBuiltIn { return device }
        }
        return nil
    }

    private static func hasInputChannels(_ device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr,
              size > 0 else { return false }
        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { buffer.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, buffer) == noErr
        else { return false }
        let list = UnsafeMutableAudioBufferListPointer(
            buffer.assumingMemoryBound(to: AudioBufferList.self))
        return list.contains { $0.mNumberChannels > 0 }
    }
}
