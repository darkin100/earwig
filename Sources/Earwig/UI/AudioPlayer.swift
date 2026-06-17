import AVFoundation
import Foundation
import Observation

/// Streams short segments of a meeting recording so the user can hear a speaker
/// before naming them. Backed by `AVPlayer`, which streams from disk rather than
/// loading the whole recording into memory (meetings can be 80 min long).
///
/// A single shared instance enforces "only one thing plays at a time": starting
/// playback elsewhere stops whatever was playing.
@Observable @MainActor
final class AudioPlayer {
    static let shared = AudioPlayer()

    /// The id of the turn (or sample) currently playing, or nil when stopped.
    private(set) var playingID: UUID?

    @ObservationIgnored private let player = AVPlayer()
    @ObservationIgnored private var currentURL: URL?
    // Boundary time observer token; removed on stop so it doesn't fire after we're done.
    @ObservationIgnored private var boundaryObserver: Any?

    private init() {}

    /// Plays `url` from `from` to `to` seconds, tagging the active segment as `id`.
    /// Stops any prior playback first and auto-stops exactly at `to`.
    func play(url: URL, from: TimeInterval, to: TimeInterval, id: UUID) {
        stop()

        if currentURL != url {
            player.replaceCurrentItem(with: AVPlayerItem(url: url))
            currentURL = url
        }

        // Auto-stop at the turn's end. Clamp so `to` is strictly after `from`.
        let end = max(to, from + 0.05)
        let endTime = CMTime(seconds: end, preferredTimescale: 600)
        boundaryObserver = player.addBoundaryTimeObserver(
            forTimes: [NSValue(time: endTime)], queue: .main
        ) { [weak self] in
            // The observer fires on the main queue; hop onto the actor to mutate state.
            MainActor.assumeIsolated {
                self?.stop()
            }
        }

        let startTime = CMTime(seconds: max(0, from), preferredTimescale: 600)
        player.seek(to: startTime, toleranceBefore: .zero, toleranceAfter: .zero)
        player.play()
        playingID = id
    }

    /// Pauses playback and clears the active segment.
    func stop() {
        player.pause()
        if let boundaryObserver {
            player.removeTimeObserver(boundaryObserver)
            self.boundaryObserver = nil
        }
        playingID = nil
    }
}
