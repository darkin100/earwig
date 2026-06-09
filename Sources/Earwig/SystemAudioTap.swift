import AVFoundation
import CoreAudio
import Foundation

/// Captures system audio (everything routed to the default output device)
/// using a CoreAudio process tap (macOS 14.4+). Unlike ScreenCaptureKit this
/// only needs the narrow "System Audio Recording Only" permission, not full
/// Screen Recording access.
final class SystemAudioTap {
    enum TapError: Error, LocalizedError {
        case coreAudio(String, OSStatus)

        var errorDescription: String? {
            switch self {
            case .coreAudio(let what, let status):
                return "\(what) failed (OSStatus \(status)). If this is the first run, grant Earwig access under System Settings > Privacy & Security > System Audio Recording Only, then try again."
            }
        }
    }

    private var tapID: AudioObjectID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID: AudioObjectID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var file: AVAudioFile?
    private var tapFormat: AVAudioFormat?
    private var loggedWriteError = false
    private let queue = DispatchQueue(label: "io.darkin.earwig.systemtap")

    func start(writingTo url: URL) throws {
        // Exclude our own process so prompt/notification chimes don't end up
        // in the meeting recording.
        var excluded: [AudioObjectID] = []
        if let selfObject = Self.processObject(for: getpid()) {
            excluded.append(selfObject)
        }

        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: excluded)
        description.name = "Earwig system audio tap"
        description.isPrivate = true

        var tap = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateProcessTap(description, &tap)
        guard status == noErr else { throw TapError.coreAudio("AudioHardwareCreateProcessTap", status) }
        tapID = tap

        do {
            // The tap's stream format (matches the output device).
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioTapPropertyFormat,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            var asbd = AudioStreamBasicDescription()
            var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            status = AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &asbd)
            guard status == noErr else { throw TapError.coreAudio("read tap format", status) }
            let sampleRate = asbd.mSampleRate > 0 ? asbd.mSampleRate : 48000

            // Aggregate device wrapping the default output device + our tap.
            let outputUID = try Self.defaultOutputDeviceUID()
            let aggregateDescription: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Earwig Tap Device",
                kAudioAggregateDeviceUIDKey: UUID().uuidString,
                kAudioAggregateDeviceMainSubDeviceKey: outputUID,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceSubDeviceListKey: [
                    [kAudioSubDeviceUIDKey: outputUID]
                ],
                kAudioAggregateDeviceTapListKey: [
                    [
                        kAudioSubTapUIDKey: description.uuid.uuidString,
                        kAudioSubTapDriftCompensationKey: true,
                    ]
                ],
            ]
            var aggregate = AudioObjectID(kAudioObjectUnknown)
            status = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregate)
            guard status == noErr else { throw TapError.coreAudio("AudioHardwareCreateAggregateDevice", status) }
            aggregateID = aggregate

            // The file is created lazily on the first IO callback so its format
            // can be derived from the buffer layout the tap actually delivers
            // (interleaved vs deinterleaved varies and a mismatch makes every
            // write fail with OSStatus -50).
            status = AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, queue) { [weak self] _, inInputData, _, _, _ in
                guard let self else { return }
                let ablPointer = UnsafeMutableAudioBufferListPointer(
                    UnsafeMutablePointer(mutating: inInputData))
                guard ablPointer.count > 0 else { return }

                if self.file == nil {
                    let bufferCount = ablPointer.count
                    let channelsPerBuffer = max(1, ablPointer[0].mNumberChannels)
                    let interleaved = bufferCount == 1
                    let channels = interleaved
                        ? AVAudioChannelCount(channelsPerBuffer)
                        : AVAudioChannelCount(bufferCount)
                    guard let format = AVAudioFormat(
                        commonFormat: .pcmFormatFloat32,
                        sampleRate: sampleRate,
                        channels: channels,
                        interleaved: interleaved) else {
                        Log.info("system tap: could not build format (buffers=\(bufferCount) ch=\(channelsPerBuffer))")
                        return
                    }
                    self.tapFormat = format
                    do {
                        self.file = try AVAudioFile(
                            forWriting: url,
                            settings: format.settings,
                            commonFormat: .pcmFormatFloat32,
                            interleaved: interleaved)
                        Log.info("system tap writing \(channels)ch \(interleaved ? "interleaved" : "deinterleaved") @ \(Int(sampleRate))Hz")
                    } catch {
                        Log.info("system tap: could not create file: \(error)")
                        return
                    }
                }

                guard let file = self.file, let format = self.tapFormat,
                      let buffer = AVAudioPCMBuffer(
                        pcmFormat: format, bufferListNoCopy: inInputData, deallocator: nil) else { return }
                do {
                    try file.write(from: buffer)
                } catch {
                    if !self.loggedWriteError {
                        self.loggedWriteError = true
                        Log.info("system tap write error: \(error)")
                    }
                }
            }
            guard status == noErr, ioProcID != nil else {
                throw TapError.coreAudio("AudioDeviceCreateIOProcIDWithBlock", status)
            }

            status = AudioDeviceStart(aggregateID, ioProcID)
            guard status == noErr else { throw TapError.coreAudio("AudioDeviceStart", status) }
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        if aggregateID != kAudioObjectUnknown, let ioProcID {
            AudioDeviceStop(aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
        }
        ioProcID = nil
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
        queue.sync { } // drain in-flight writes
        file = nil
        tapFormat = nil
        loggedWriteError = false
    }

    // MARK: helpers

    private static func defaultOutputDeviceUID() throws -> String {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        guard status == noErr, deviceID != 0 else {
            throw TapError.coreAudio("get default output device", status)
        }

        var uid: CFString = "" as CFString
        size = UInt32(MemoryLayout<CFString>.size)
        address.mSelector = kAudioDevicePropertyDeviceUID
        status = withUnsafeMutablePointer(to: &uid) { ptr in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, ptr)
        }
        guard status == noErr else { throw TapError.coreAudio("get output device UID", status) }
        return uid as String
    }

    private static func processObject(for pid: pid_t) -> AudioObjectID? {
        var processObject = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var mutablePID = pid
        let status = withUnsafePointer(to: &mutablePID) { pidPtr in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject), &address,
                UInt32(MemoryLayout<pid_t>.size), pidPtr, &size, &processObject)
        }
        guard status == noErr, processObject != kAudioObjectUnknown else { return nil }
        return processObject
    }
}
