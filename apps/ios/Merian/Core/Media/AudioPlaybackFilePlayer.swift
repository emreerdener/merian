import AVFoundation
import Foundation

struct AudioPlaybackSnapshot: Sendable {
    let currentTime: TimeInterval
    let duration: TimeInterval
    let isPlaying: Bool
}

protocol AudioPlaybackDriver: Sendable {
    func load(delegate: AudioPlayerDelegate) async throws -> AudioPlaybackSnapshot
    func play() async -> AudioPlaybackSnapshot
    func pause() async
    func stop() async
    func seek(to time: TimeInterval) async
    func snapshot() async -> AudioPlaybackSnapshot
    func dispose() async
}

private final class AudioPlaybackExecutor: SerialExecutor {
    private let queue = DispatchQueue(label: "app.merian.carousel-audio", qos: .userInitiated)

    func enqueue(_ job: consuming ExecutorJob) {
        let job = UnownedJob(job)
        let executor = asUnownedSerialExecutor()
        queue.async { job.runSynchronously(on: executor) }
    }
}

/// AVAudioPlayer never leaves this executor, including its final release.
actor AudioPlaybackFileDriver: AudioPlaybackDriver {
    private static let executor = AudioPlaybackExecutor()
    nonisolated var unownedExecutor: UnownedSerialExecutor {
        Self.executor.asUnownedSerialExecutor()
    }
    private let url: URL
    private let makePlayer: @Sendable (URL) throws -> AVAudioPlayer
    private var player: AVAudioPlayer?

    init(
        url: URL,
        makePlayer: @escaping @Sendable (URL) throws -> AVAudioPlayer = {
            try AVAudioPlayer(contentsOf: $0)
        }
    ) {
        self.url = url
        self.makePlayer = makePlayer
    }

    func load(delegate: AudioPlayerDelegate) throws -> AudioPlaybackSnapshot {
        try Task.checkCancellation()
        let player = try makePlayer(url)
        player.delegate = delegate
        self.player = player
        // Do not prepareToPlay here: even silent preparation activates the session.
        return snapshot()
    }

    func play() -> AudioPlaybackSnapshot {
        _ = player?.play()
        return snapshot()
    }
    func pause() { player?.pause() }
    func stop() { player?.stop() }
    func seek(to time: TimeInterval) { player?.currentTime = time }
    func snapshot() -> AudioPlaybackSnapshot {
        AudioPlaybackSnapshot(
            currentTime: player?.currentTime ?? 0,
            duration: player?.duration ?? 0,
            isPlaying: player?.isPlaying == true
        )
    }
    func dispose() {
        player?.stop()
        player?.delegate = nil
        player = nil
    }
}

/// UI projection of one player. Commands are ordered, and every suspension is
/// fenced so a late play or time sample cannot undo a newer pause, seek or stop.
@MainActor
final class AudioPlaybackFilePlayer {
    private let driver: any AudioPlaybackDriver
    private let delegate = AudioPlayerDelegate()
    private var tail: Task<Void, Never>?
    private var revision = 0
    private var playbackRevision = 0
    private var acceptsCallbacks = false
    private var sampledTime: TimeInterval = 0
    private var sampledAt = ContinuousClock.now
    private(set) var duration: TimeInterval = 0
    private(set) var isPlaying = false
    var onFinish: (ObjectIdentifier, Bool) -> Void = { _, _ in }
    var onDecodeError: (ObjectIdentifier, String?) -> Void = { _, _ in }

    var currentTime: TimeInterval {
        get {
            let elapsed = isPlaying ? sampledAt.duration(to: .now).components : nil
            let seconds = elapsed.map { Double($0.seconds) + Double($0.attoseconds) / 1e18 } ?? 0
            return min(duration, max(0, sampledTime + seconds))
        }
        set {
            revision &+= 1
            sampledTime = min(duration, max(0, newValue))
            sampledAt = .now
            let time = sampledTime
            enqueue { await $0.seek(to: time) }
        }
    }

    init(driver: any AudioPlaybackDriver) {
        self.driver = driver
        delegate.onFinish = { [weak self] _, success in
            guard let self, acceptsCallbacks else { return }
            revision &+= 1
            playbackRevision &+= 1
            acceptsCallbacks = false
            pauseProjection()
            onFinish(ObjectIdentifier(self), success)
        }
        delegate.onDecodeError = { [weak self] _, error in
            guard let self, acceptsCallbacks else { return }
            revision &+= 1
            playbackRevision &+= 1
            acceptsCallbacks = false
            pauseProjection()
            onDecodeError(ObjectIdentifier(self), error)
        }
    }

    func load() async throws {
        let snapshot = try await driver.load(delegate: delegate)
        try Task.checkCancellation()
        duration = snapshot.duration
        apply(snapshot)
    }

    func play() async -> Bool {
        guard !Task.isCancelled else { return false }
        let expectedPlaybackRevision = playbackRevision
        let expectedRevision = revision
        let preceding = tail
        let driver = driver
        let operation = Task { [weak self] in
            await preceding?.value
            guard let self, playbackRevision == expectedPlaybackRevision else { return false }
            acceptsCallbacks = true
            let snapshot = await driver.play()
            guard playbackRevision == expectedPlaybackRevision else { return false }
            if revision == expectedRevision {
                apply(snapshot)
            } else {
                // A seek during startup preserves play intent and its newer position.
                isPlaying = snapshot.isPlaying
                sampledAt = .now
            }
            return snapshot.isPlaying
        }
        tail = Task { _ = await operation.value }
        return await operation.value
    }

    func pause() {
        revision &+= 1
        playbackRevision &+= 1
        acceptsCallbacks = false
        pauseProjection()
        enqueue { await $0.pause() }
    }

    @discardableResult
    func stop() -> Task<Void, Never> {
        revision &+= 1
        playbackRevision &+= 1
        acceptsCallbacks = false
        pauseProjection()
        return enqueue { await $0.stop() }
    }

    func waitForRetirement(_ retirement: Task<Void, Never>?) {
        let preceding = tail
        tail = Task {
            await preceding?.value
            await retirement?.value
        }
    }

    func refresh() async {
        let expectedRevision = revision
        let preceding = tail
        await preceding?.value
        guard revision == expectedRevision else { return }
        let snapshot = await driver.snapshot()
        guard revision == expectedRevision else { return }
        apply(snapshot)
    }

    private func pauseProjection() {
        sampledTime = currentTime
        sampledAt = .now
        isPlaying = false
    }

    private func apply(_ snapshot: AudioPlaybackSnapshot) {
        sampledTime = snapshot.currentTime
        sampledAt = .now
        isPlaying = snapshot.isPlaying
    }

    @discardableResult
    private func enqueue(
        _ operation: @escaping @Sendable (any AudioPlaybackDriver) async -> Void
    ) -> Task<Void, Never> {
        let preceding = tail
        let driver = driver
        let task = Task {
            await preceding?.value
            await operation(driver)
        }
        tail = task
        return task
    }

    deinit {
        let preceding = tail
        let driver = driver
        Task {
            await preceding?.value
            await driver.dispose()
        }
    }
}
