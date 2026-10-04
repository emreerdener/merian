import AVFoundation
import Observation

@MainActor
@Observable
final class StagedVideoPreviewPlayback {
    struct Dependencies {
        var play: @MainActor (AVPlayer) -> Void = { $0.play() }
        var pause: @MainActor (AVPlayer) -> Void = { $0.pause() }
        var makeBoostedItem: @MainActor (URL, URL) async throws -> AVPlayerItem = {
            try await StagedVideoPreviewComposition.makeItem(videoURL: $0, boostedAudioURL: $1)
        }
        var seek: @MainActor (AVPlayer, CMTime) async -> Bool = {
            await StagedVideoPreviewPlayback.seekWhenReady(player: $0, time: $1)
        }
    }

    let player: AVPlayer
    let canBoost: Bool
    private(set) var isBoostEnabled = false
    private(set) var isPreparing = false
    private(set) var isSwitchingSource = false
    private(set) var hasBoostFailure = false

    @ObservationIgnored private let videoURL: URL
    @ObservationIgnored private let audioPath: String?
    @ObservationIgnored private let boostSource: StagedPreviewAudioBoostSource
    @ObservationIgnored private let session: AudioPlaybackSessionController
    @ObservationIgnored private let dependencies: Dependencies
    @ObservationIgnored private var preparationTask: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var lifecycle = UUID()
    @ObservationIgnored private var isActive = false

    init(
        video: StagedVideo,
        boostSource: StagedPreviewAudioBoostSource? = nil,
        session: AudioPlaybackSessionController? = nil,
        dependencies: Dependencies? = nil
    ) {
        videoURL = URL(fileURLWithPath: video.filePath)
        audioPath = video.audioFilePath
        canBoost = video.audioFilePath != nil
        player = AVPlayer(url: videoURL)
        self.boostSource = boostSource ?? .init()
        self.session = session ?? .init()
        self.dependencies = dependencies ?? .init()
    }

    var boostTitle: String {
        if isPreparing { return isBoostEnabled ? "Reverting…" : "Boosting…" }
        return isBoostEnabled ? "Boosted audio" : "Boost audio"
    }

    var boostAccessibilityLabel: String {
        if isPreparing { return boostTitle }
        return isBoostEnabled ? "Turn off audio boost" : "Boost audio"
    }

    func start() async {
        isActive = true
        let expected = lifecycle
        let activated = await session.activate()
        guard activated, isActive, lifecycle == expected, !Task.isCancelled else { return }
        dependencies.play(player)
    }

    @discardableResult
    func toggleBoost() -> Task<Void, Never>? {
        guard isActive, canBoost, !isPreparing else { return nil }
        let enable = !isBoostEnabled
        let request = UUID()
        generation = request
        isPreparing = true
        hasBoostFailure = false
        preparationTask = Task { [weak self] in
            await self?.changeSource(enable: enable, request: request)
        }
        return preparationTask
    }

    /// Stops pending preparation/resume without changing the user's paused position.
    func pauseForBackground() {
        lifecycle = UUID()
        cancelPreparation()
        dependencies.pause(player)
        session.cancelPendingActivation()
    }

    func stop() {
        isActive = false
        lifecycle = UUID()
        cancelPreparation()
        dependencies.pause(player)
        player.replaceCurrentItem(with: nil)
        boostSource.release()
        session.deactivate()
    }

    private func cancelPreparation() {
        generation = UUID()
        preparationTask?.cancel()
        preparationTask = nil
        isPreparing = false
        isSwitchingSource = false
    }

    private func changeSource(enable: Bool, request: UUID) async {
        defer {
            if generation == request {
                preparationTask = nil
                isPreparing = false
                isSwitchingSource = false
            }
        }
        do {
            let replacement: AVPlayerItem
            if enable, let audioPath {
                let result = try await boostSource.prepare(source: audioPath)
                replacement = try await dependencies.makeBoostedItem(videoURL, result.url)
            } else {
                replacement = AVPlayerItem(url: videoURL)
            }
            guard accepts(request) else { return }
            // Sample after preparation: native playback/seeking remains usable during DSP.
            let time = player.currentTime()
            let shouldResume = player.rate != 0
            let prior = player.currentItem
            let priorBoostEnabled = isBoostEnabled
            dependencies.pause(player)
            isSwitchingSource = true
            player.replaceCurrentItem(with: replacement)
            isBoostEnabled = enable
            let positioned = await dependencies.seek(player, time.isNumeric ? time : .zero)
            guard accepts(request) else { return }
            guard positioned else {
                player.replaceCurrentItem(with: prior)
                isBoostEnabled = priorBoostEnabled
                _ = await dependencies.seek(player, time.isNumeric ? time : .zero)
                guard accepts(request) else { return }
                hasBoostFailure = true
                if shouldResume { await resume(request: request) }
                return
            }
            if shouldResume { await resume(request: request) }
        } catch {
            guard accepts(request) else { return }
            // Preparation never replaces the original item until it has succeeded.
            hasBoostFailure = true
        }
    }

    private func resume(request: UUID) async {
        let activated = await session.activate()
        guard activated, accepts(request) else { return }
        dependencies.play(player)
    }

    private func accepts(_ request: UUID) -> Bool {
        isActive && generation == request && !Task.isCancelled
    }

    private static func seekWhenReady(player: AVPlayer, time: CMTime) async -> Bool {
        guard let item = player.currentItem else { return false }
        let deadline = ContinuousClock.now + .seconds(5)
        // A newly installed item can acknowledge a seek before readiness, then reset
        // its timeline to zero. Keep the switch pending until its timeline is usable.
        while item.status == .unknown, ContinuousClock.now < deadline {
            guard !Task.isCancelled, player.currentItem === item else { return false }
            do { try await Task.sleep(for: .milliseconds(20)) } catch { return false }
        }
        guard !Task.isCancelled, player.currentItem === item, item.status == .readyToPlay else { return false }
        return await player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }
}
