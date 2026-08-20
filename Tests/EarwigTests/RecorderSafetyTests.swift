import AVFoundation
import Foundation
import Testing

@testable import EarwigKit

/// Guards for the audio-capture start path: a raised Objective-C exception
/// must become a Swift error rather than aborting the process (an uncaught
/// one from installTapOnBus crashed the app on 2026-08-20), and formats a
/// switching input device publishes must be rejected before they get there.
struct RecorderSafetyTests {
    @Test func raisedObjCExceptionBecomesSwiftError() {
        var caught: Error?
        do {
            try withObjCExceptionCatching {
                NSException(
                    name: .invalidArgumentException,
                    reason: "required condition is false: format.sampleRate == hwFormat.sampleRate",
                    userInfo: nil
                ).raise()
            }
        } catch {
            caught = error
        }
        #expect(caught != nil)
        #expect((caught as NSError?)?.localizedDescription.contains("hwFormat.sampleRate") == true)
    }

    @Test func blockThatDoesNotRaisePassesThrough() throws {
        var ran = false
        try withObjCExceptionCatching { ran = true }
        #expect(ran)
    }

    @Test func inputFormatsAreValidatedBeforeUse() {
        // Real devices: AirPods in hands-free mode, built-in mic.
        #expect(Recorder.isUsableInputFormat(sampleRate: 24000, channelCount: 1))
        #expect(Recorder.isUsableInputFormat(sampleRate: 48000, channelCount: 2))
        // Published while a device is being torn down / re-advertised.
        #expect(!Recorder.isUsableInputFormat(sampleRate: 0, channelCount: 1))
        #expect(!Recorder.isUsableInputFormat(sampleRate: 48000, channelCount: 0))
        #expect(!Recorder.isUsableInputFormat(sampleRate: 0, channelCount: 0))
    }
}
