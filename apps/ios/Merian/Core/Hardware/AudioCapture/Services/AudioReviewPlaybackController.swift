import Foundation

/// Owns presentation and task/session lifetime; the player owns hardware work.
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
            makePlayer: { AudioReviewPlaybackFilePlayer(contentsOf: $0) },
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
        let onProgress: ProgressHandler
        let onCompletion: CompletionHandler
        let onStartFailure: CompletionHandler
        var progress: Double
        var duration: TimeInterval = 0
        var seekRevision = 0
        var isPlaying = false
        var activationTask: Task<Void, Never>?
        var lease: AudioSessionCoordinator.Lease?
        var seekTask: Task<Void, Never>?
        var progressTask: Task<Void, Never>?
        var completionTask: Task<Void, Never>?
    }

    private let dependencies: Dependencies
    private var activePlayback: ActivePlayback?
    private var retirementTask: Task<Double, Never>?

    init(dependencies: Dependencies = .live) { self.dependencies = dependencies }

    @discardableResult
    func start(
        fileURL: URL,
        resumeProgress: Double,
        replacingCurrent: Bool = false,
        onProgress: @escaping ProgressHandler,
        onCompletion: @escaping CompletionHandler,
        onStartFailure: CompletionHandler? = nil
    ) -> Bool {
        guard replacingCurrent || activePlayback == nil,
              let player = try? dependencies.makePlayer(fileURL) else { return false }
        let preservesPosition = replacingCurrent && activePlayback != nil
        stop()
        let retirement = retirementTask
        let generation = UUID()
        activePlayback = ActivePlayback(
            generation: generation, player: player,
            onProgress: onProgress, onCompletion: onCompletion,
            onStartFailure: onStartFailure ?? onCompletion,
            progress: min(1, max(0, resumeProgress))
        )
        activePlayback?.activationTask = Task { [weak self] in
            guard let self else { return }
            let previousProgress = await retirement?.value
            guard isCurrent(generation), !Task.isCancelled else { return }
            if preservesPosition, let previousProgress, activePlayback?.seekRevision == 0 {
                activePlayback?.progress = previousProgress
                onProgress(previousProgress)
            }
            do {
                let duration = try await player.prepare()
                guard isCurrent(generation), !Task.isCancelled else { return }
                activePlayback?.duration = duration
            } catch { finishIfCurrent(generation, failedToStart: true); return }
            let lease: AudioSessionCoordinator.Lease
            do { lease = try await dependencies.activateSession() } catch {
                finishIfCurrent(generation)
                return
            }
            guard isCurrent(generation), !Task.isCancelled else {
                await dependencies.deactivateSession(lease)
                return
            }
            activePlayback?.lease = lease
            await synchronizePosition(generation)
            guard isCurrent(generation), !Task.isCancelled else { return }
            let revision = activePlayback?.seekRevision
            let started = await player.play()
            guard isCurrent(generation), !Task.isCancelled else { return }
            guard started else { finishIfCurrent(generation, failedToStart: true); return }
            activePlayback?.isPlaying = true
            if revision != activePlayback?.seekRevision {
                await synchronizePosition(generation)
            }
            guard isCurrent(generation), !Task.isCancelled else { return }
            startProgress(generation)
            scheduleCompletion()
        }
        return true
    }

    func stop() {
        guard let playback = activePlayback else { return }
        activePlayback = nil
        playback.activationTask?.cancel()
        playback.seekTask?.cancel()
        playback.progressTask?.cancel()
        playback.completionTask?.cancel()
        let priorRetirement = retirementTask
        let deactivateSession = dependencies.deactivateSession
        retirementTask = Task {
            // Join in-flight operations before stop: an uncancellable late play
            // must not restart audio after teardown, or overlap its replacement.
            _ = await priorRetirement?.value
            await playback.activationTask?.value
            await playback.seekTask?.value
            let time = await playback.player.playbackTime()
            await playback.player.stop()
            if let lease = playback.lease { await deactivateSession(lease) }
            return playback.isPlaying && playback.seekTask == nil && playback.duration > 0
                ? min(1, max(0, time / playback.duration)) : playback.progress
        }
    }

    func seek(to progress: Double) {
        guard activePlayback != nil else { return }
        activePlayback?.progress = min(1, max(0, progress))
        activePlayback?.seekRevision += 1
        activePlayback?.completionTask?.cancel()
        activePlayback?.seekTask?.cancel()
        guard let playback = activePlayback, playback.isPlaying else { return }
        activePlayback?.seekTask = Task { [weak self] in
            guard let self else { return }
            await synchronizePosition(playback.generation)
            guard isCurrent(playback.generation), !Task.isCancelled else { return }
            activePlayback?.seekTask = nil
            scheduleCompletion()
        }
    }

    private func synchronizePosition(_ generation: UUID) async {
        while let playback = activePlayback,
              playback.generation == generation, !Task.isCancelled {
            await playback.player.seek(to: playback.progress * playback.duration)
            guard playback.seekRevision != activePlayback?.seekRevision else { return }
        }
    }

    private func startProgress(_ generation: UUID) {
        activePlayback?.progressTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do { try await dependencies.waitForProgressTick() } catch { return }
                guard let playback = activePlayback,
                      playback.generation == generation, !Task.isCancelled else { return }
                guard playback.seekTask == nil else { continue }
                let time = await playback.player.playbackTime()
                guard isCurrent(generation), !Task.isCancelled,
                      activePlayback?.seekTask == nil,
                      activePlayback?.seekRevision == playback.seekRevision else { continue }
                let progress = playback.duration > 0
                    ? min(1, max(0, time / playback.duration)) : 0
                activePlayback?.progress = progress
                playback.onProgress(progress)
            }
        }
    }

    private func scheduleCompletion() {
        guard let playback = activePlayback else { return }
        playback.completionTask?.cancel()
        let remaining = max(0, playback.duration - playback.duration * playback.progress)
        activePlayback?.completionTask = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            do { try await dependencies.waitForCompletion(remaining) } catch {
                if Task.isCancelled { return }
            }
            guard !Task.isCancelled else { return }
            finishIfCurrent(playback.generation)
        }
    }

    private func finishIfCurrent(_ generation: UUID, failedToStart: Bool = false) {
        guard let playback = activePlayback, playback.generation == generation else { return }
        stop()
        if failedToStart { playback.onStartFailure() } else { playback.onCompletion() }
    }

    private func isCurrent(_ generation: UUID) -> Bool {
        activePlayback?.generation == generation
    }
}
