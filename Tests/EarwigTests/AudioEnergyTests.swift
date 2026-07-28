import AVFoundation
import Foundation
import Testing

@testable import EarwigKit

/// The mic-channel energy gate: room ambience must measure below the speech
/// floor, actual speech-level audio above it.
struct AudioEnergyTests {
    private func makeAudioFile(silentSeconds: Double, toneSeconds: Double) throws -> URL {
        let sampleRate = 16_000.0
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
            channels: 1, interleaved: false)!
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("earwig-test-\(UUID().uuidString).caf")
        let file = try AVAudioFile(forWriting: url, settings: format.settings,
                                   commonFormat: .pcmFormatFloat32, interleaved: false)

        let silentFrames = AVAudioFrameCount(silentSeconds * sampleRate)
        if silentFrames > 0 {
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: silentFrames)!
            buffer.frameLength = silentFrames // zero-filled
            try file.write(from: buffer)
        }
        let toneFrames = AVAudioFrameCount(toneSeconds * sampleRate)
        if toneFrames > 0 {
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: toneFrames)!
            buffer.frameLength = toneFrames
            let data = buffer.floatChannelData![0]
            for frame in 0..<Int(toneFrames) {
                data[frame] = 0.3 * sin(2 * .pi * 220 * Float(frame) / Float(sampleRate))
            }
            try file.write(from: buffer)
        }
        return url
    }

    @Test func silenceMeasuresBelowSpeechFloorAndToneAbove() throws {
        let url = try makeAudioFile(silentSeconds: 1, toneSeconds: 1)
        defer { try? FileManager.default.removeItem(at: url) }
        let file = try AVAudioFile(forReading: url)

        let silence = try #require(Diarizer.speechEnergy(file: file, start: 0, end: 0.9))
        let tone = try #require(Diarizer.speechEnergy(file: file, start: 1.1, end: 1.9))

        #expect(silence < 0.004, "silence must sit below the energy gate")
        #expect(tone > 0.004, "speech-level audio must pass the energy gate")
    }

    @Test func invalidRangeReturnsNil() throws {
        let url = try makeAudioFile(silentSeconds: 0.5, toneSeconds: 0)
        defer { try? FileManager.default.removeItem(at: url) }
        let file = try AVAudioFile(forReading: url)
        #expect(Diarizer.speechEnergy(file: file, start: 2, end: 1) == nil)
    }
}
