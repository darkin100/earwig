import Foundation
import Testing

@testable import EarwigKit

/// Guards for the system tap's sample-rate policy.
///
/// Activating the microphone drops a Bluetooth headset — and with it the whole
/// audio device — into call mode at 16kHz (24kHz on newer hardware), while the
/// process tap carries on declaring the 48kHz it was created with. Believing
/// the tap writes 16kHz samples into a 48kHz file: the meeting plays back at 3x
/// speed, transcribes to gibberish, and diarization collapses. That shipped
/// once (fixed 2026-07-28) and the fix itself had no coverage, so a refactor
/// could have quietly undone it.
struct SystemTapSampleRateTests {

    // MARK: which rate the file is opened at

    @Test func deviceInCallModeOverridesTheRateTheTapDeclares() {
        // The failure this whole policy exists for.
        #expect(SystemAudioTap.resolvedSampleRate(declared: 48000, device: 16000) == 16000)
        // Newer headsets land here instead; same bug, 2x rather than 3x.
        #expect(SystemAudioTap.resolvedSampleRate(declared: 48000, device: 24000) == 24000)
    }

    @Test func theDeviceRateWinsEvenWhenItIsHigherThanDeclared() {
        // Leaving call mode is the same mismatch in the other direction —
        // the policy is "trust the device", not "trust the lower number".
        #expect(SystemAudioTap.resolvedSampleRate(declared: 16000, device: 48000) == 48000)
    }

    @Test func theDeclaredRateIsKeptWhenTheDeviceWillNotReportOne() {
        // Property read failed, or the aggregate device has gone away.
        #expect(SystemAudioTap.resolvedSampleRate(declared: 48000, device: nil) == 48000)
        // A device reporting 0Hz is not a device running at 0Hz.
        #expect(SystemAudioTap.resolvedSampleRate(declared: 48000, device: 0) == 48000)
    }

    @Test func aUsableRateIsProducedEvenWhenNeitherSourceIsCredible() {
        // Both unreadable: guessing 48kHz beats building no format at all,
        // which would drop the system channel for the entire meeting.
        #expect(SystemAudioTap.resolvedSampleRate(declared: 0, device: nil)
            == SystemAudioTap.assumedSampleRate)
        // A live device rate rescues a tap that declared nothing.
        #expect(SystemAudioTap.resolvedSampleRate(declared: 0, device: 16000) == 16000)
    }

    @Test func agreeingSourcesResolveToTheRateTheyAgreeOn() {
        #expect(SystemAudioTap.resolvedSampleRate(declared: 48000, device: 48000) == 48000)
    }

    // MARK: detecting the drop once recording is under way

    @Test func droppingIntoCallModeMidRecordingIsFlagged() {
        // Someone joins the call after recording started: the file is already
        // open at 48kHz and everything from here is mis-timed.
        #expect(SystemAudioTap.isMeaningfulRateChange(from: 48000, to: 16000))
        #expect(SystemAudioTap.isMeaningfulRateChange(from: 48000, to: 24000))
        // And leaving call mode again.
        #expect(SystemAudioTap.isMeaningfulRateChange(from: 16000, to: 48000))
    }

    @Test func aSteadyRateIsNotFlagged() {
        #expect(!SystemAudioTap.isMeaningfulRateChange(from: 48000, to: 48000))
        // Sub-1Hz jitter in a reported rate is not a mode switch.
        #expect(!SystemAudioTap.isMeaningfulRateChange(from: 48000, to: 48000.4))
    }

    @Test func noChangeIsReportedBeforeTheFileExists() {
        // The listener can fire before the first buffer opened the file; there
        // is no rate to have changed from yet.
        #expect(!SystemAudioTap.isMeaningfulRateChange(from: 0, to: 16000))
    }

    @Test func aFailedRateReadIsNotMistakenForACollapseToZero() {
        // nominalSampleRate returns nil -> 0 on a read failure. Warning that
        // the device "changed to 0Hz" would be false, and would bury the real
        // warning this listener exists to produce.
        #expect(!SystemAudioTap.isMeaningfulRateChange(from: 48000, to: 0))
    }
}
