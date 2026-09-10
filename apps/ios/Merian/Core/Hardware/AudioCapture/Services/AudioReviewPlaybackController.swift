import AVFoundation
import Foundation

@MainActor
protocol AudioReviewPlaybackPlayer: AnyObject {
    var duration: TimeInterval { get }
    var currentTime: TimeInterval { get set }

    @discardableResult
    func play() -> Bool
    func stop()
}

extension AVAudioPlayer: AudioReviewPlaybackPlayer {}

/// Owns review-player, progress-task, completion-task, and audio-session lifetime.
///
/// Every asynchronous path carries a generation so cancellation that completes
/// cooperatively cannot publish progress or finish a replacement playback.
@MainActor
final class AudioReviewPlaybackController {
    struct Dependencies: Sendable {
        let makePlayer:
            @MainActor @Sendable (URL) throws -> any AudioReviewPlaybackPlayer
        let activateSession:
            @Sendable () async throws -> AudioSessionCoordinator.Lease
        let deactivateSession:
            @Sendable (AudioSessionCoordinator.Lease) async -> Void
        let waitForProgressTick: @Sendable () async throws -> Void
        let waitForCompletion:
            @Sendable (_ remainingDuration: TimeInterval) async throws -> Void

        static let live = Self(
            makePlayer: { try AVAudioPlayer(contentsOf: $0) },
            activateSession: {
                try await AudioSessionCoordinator.shared.activate(.playback)
            },
            deactivateSession: { lease in
                await AudioSessionCoordinator.shared.deactivate(
                    ifCurrent: lease
                )
            },
            waitForProgressTick: {
                try await Task.sleep(nanoseconds: 33_000_000)
            },
            waitForCompletion: { remainingDuration in
                let nanoseconds = UInt64(
                    (remainingDuration + 0.3) * 1_000_000_000
                )
                try await Task.sleep(nanoseconds: nanoseconds)
            }
        )
    }

    typealias ProgressHandler = @MainActor @Sendable (Double) -> Void
    typealias CompletionHandler = @MainActor @Sendable () -> Void

    private struct ActivePlayback {
        let generation: UUID
        let player: any AudioReviewPlaybackPlayer
        var lease: AudioSessionCoordinator.Lease?
        var progressTask: Task<Void, Never>?
        var completionTask: Task<Void, Never>?
    }

    private let dependencies: Dependencies
    private var activePlayback: ActivePlayback?

    init(dependencies: Dependencies = .live) {
        self.dependencies = dependencies
    }

    @discardableResult
    func start(
        fileURL: URL,
        resumeProgress: Double,
        onProgress: @escaping ProgressHandler,
        onCompletion: @escaping CompletionHandler
    ) -> Bool {
        guard activePlayback == nil,
              let player = try? dependencies.makePlayer(fileURL) else {
            return false
        }

        let generation = UUID()
        activePlayback = ActivePlayback(
            generation: generation,
            player: player
        )

        let progressTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    try await dependencies.waitForProgressTick()
                } catch {
                    return
                }
                guard !Task.isCancelled,
                      isCurrent(generation, player: player) else {
                    return
                }
                let progress = player.duration > 0
                    ? player.currentTime / player.duration
                    : 0
                onProgress(min(1, max(0, progress)))
            }
        }
        activePlayback?.progressTask = progressTask

        let completionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let lease: AudioSessionCoordinator.Lease
            do {
                lease = try await dependencies.activateSession()
            } catch {
                finishIfCurrent(
                    generation,
                    player: player,
                    onCompletion: onCompletion
                )
                return
            }

            guard !Task.isCancelled,
                  install(
                      lease: lease,
                      generation: generation,
                      player: player
                  ) else {
                await dependencies.deactivateSession(lease)
                return
            }

            let clampedResumeProgress = min(1, max(0, resumeProgress))
            if clampedResumeProgress > 0 {
                player.currentTime = player.duration * clampedResumeProgress
            }
            guard player.play() else {
                finishIfCurrent(
                    generation,
                    player: player,
                    onCompletion: onCompletion
                )
                return
            }

            let remainingDuration = max(
                0,
                player.duration * (1 - clampedResumeProgress)
            )
            do {
                try await dependencies.waitForCompletion(remainingDuration)
            } catch {
                finishIfCurrent(
                    generation,
                    player: player,
                    onCompletion: onCompletion
                )
                return
            }
            guard !Task.isCancelled else { return }
            finishIfCurrent(
                generation,
                player: player,
                onCompletion: onCompletion
            )
        }
        activePlayback?.completionTask = completionTask
        return true
    }

    func stop() {
        guard let playback = activePlayback else { return }
        activePlayback = nil
        playback.progressTask?.cancel()
        playback.completionTask?.cancel()
        playback.player.stop()
        deactivate(playback.lease)
    }

    func seek(to progress: Double) {
        guard let playback = activePlayback else { return }
        let clamped = min(1, max(0, progress))
        playback.player.currentTime = playback.player.duration * clamped
    }

    private func install(
        lease: AudioSessionCoordinator.Lease,
        generation: UUID,
        player: any AudioReviewPlaybackPlayer
    ) -> Bool {
        guard var playback = activePlayback,
              playback.generation == generation,
              playback.player === player else {
            return false
        }
        playback.lease = lease
        activePlayback = playback
        return true
    }

    private func finishIfCurrent(
        _ generation: UUID,
        player: any AudioReviewPlaybackPlayer,
        onCompletion: CompletionHandler
    ) {
        guard let playback = activePlayback,
              playback.generation == generation,
              playback.player === player else {
            return
        }
        activePlayback = nil
        playback.progressTask?.cancel()
        playback.player.stop()
        deactivate(playback.lease)
        onCompletion()
    }

    private func isCurrent(
        _ generation: UUID,
        player: any AudioReviewPlaybackPlayer
    ) -> Bool {
        guard let playback = activePlayback else { return false }
        return playback.generation == generation
            && playback.player === player
    }

    private func deactivate(_ lease: AudioSessionCoordinator.Lease?) {
        guard let lease else { return }
        let deactivateSession = dependencies.deactivateSession
        Task {
            await deactivateSession(lease)
        }
    }
}
