import AVFoundation
import Foundation

protocol AudioReviewPlaybackPlayer: AnyObject, Sendable {
    func prepare() async throws -> TimeInterval
    func playbackTime() async -> TimeInterval
    func seek(to time: TimeInterval) async
    func play() async -> Bool
    func stop() async
}

/// Blocking audio-driver calls use a dedicated queue, not the UI thread or
/// Swift's cooperative executor pool. Only actor jobs cross this boundary.
private final class AudioReviewPlaybackExecutor: SerialExecutor {
    private let queue = DispatchQueue(label: "app.merian.audio-review", qos: .userInitiated)

    func enqueue(_ job: consuming ExecutorJob) {
        let job = UnownedJob(job)
        let executor = asUnownedSerialExecutor()
        queue.async { job.runSynchronously(on: executor) }
    }
}

/// Confines the non-Sendable player to one executor. AVAudioPlayer.play() and
/// stop() synchronously acquire/release audio hardware, even with an active
/// AVAudioSession, so neither may run on the presentation actor.
actor AudioReviewPlaybackFilePlayer: AudioReviewPlaybackPlayer {
    private static let executor = AudioReviewPlaybackExecutor()
    nonisolated var unownedExecutor: UnownedSerialExecutor {
        Self.executor.asUnownedSerialExecutor()
    }

    private let url: URL
    private let makePlayer: @Sendable (URL) throws -> AVAudioPlayer
    private var player: AVAudioPlayer?

    init(
        contentsOf url: URL,
        makePlayer: @escaping @Sendable (URL) throws -> AVAudioPlayer = {
            try AVAudioPlayer(contentsOf: $0)
        }
    ) {
        self.url = url
        self.makePlayer = makePlayer
    }

    func prepare() throws -> TimeInterval {
        try Task.checkCancellation()
        let player = try makePlayer(url)
        self.player = player
        return player.duration
    }

    func playbackTime() -> TimeInterval { player?.currentTime ?? 0 }

    func seek(to time: TimeInterval) {
        guard !Task.isCancelled else { return }
        player?.currentTime = time
    }

    func play() -> Bool {
        guard !Task.isCancelled else { return false }
        return player?.play() ?? false
    }

    func stop() { player?.stop() }
}
