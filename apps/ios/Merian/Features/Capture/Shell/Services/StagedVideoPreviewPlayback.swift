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

    let lifetime = MediaPlaybackLifetime()
    let player: AVPlayer
    let canBoost: Bool
    private(set) var isBoostEnabled = false
    private(set) var isPreparing = false
    private(set) var isSwitchingSource = false
    private(set) var hasBoostFailure = false
    private(set) var isPlaying = false
    private(set) var isStartingPlayback = false
    private(set) var elapsed: Double = 0
    private(set) var duration: Double = 0
    private(set) var isMuted = false
    @ObservationIgnored private var controlTask: Task<Void, Never>?
    @ObservationIgnored private var controlGeneration = UUID()

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
        previewURL: URL? = nil,
        boostSource: StagedPreviewAudioBoostSource? = nil,
        session: AudioPlaybackSessionController? = nil,
        dependencies: Dependencies? = nil
    ) {
        videoURL = previewURL ?? StagedVideo.localURL(for: video.filePath)
        audioPath = video.audioFilePath
        canBoost = video.audioFilePath != nil
        player = AVPlayer()
        self.boostSource = boostSource ?? .init()
        self.session = session ?? .init()
        self.dependencies = dependencies ?? .init()
        // Registration precedes the first AVPlayerItem or asynchronous source read.
        try? lifetime.configure(stop: { [weak self] in self?.quiesce() }, finish: { [weak self] in
            self?.boostSource.release()
            self?.session.deactivate()
        })
    }

    var boostTitle: String {
        if isPreparing { return isBoostEnabled ? "Reverting…" : "Boosting…" }
        return isBoostEnabled ? "Boosted audio" : "Boost audio"
    }

    var boostAccessibilityLabel: String {
        if isPreparing { return boostTitle }
        return isBoostEnabled ? "Turn off audio boost" : "Boost audio"
    }

    func start(autoplay: Bool = true) async {
        await lifetime.run { [self] in
            isActive = true
            if player.currentItem == nil { player.replaceCurrentItem(with: AVPlayerItem(url: videoURL)) }
            let expected = lifecycle
            let activated = await session.activate()
            guard activated, isActive, lifecycle == expected, !Task.isCancelled else { return }
            if autoplay { dependencies.play(player) }
            refreshProgress()
        }
    }

    func refreshProgress() {
        let current = player.currentTime().seconds
        let total = player.currentItem?.duration.seconds ?? 0
        elapsed = current.isFinite ? max(0, current) : 0
        duration = total.isFinite ? max(0, total) : 0
        isPlaying = player.rate != 0
    }

    func togglePlayback() {
        guard self.isActive, !isSwitchingSource else { return }
        self.controlGeneration = UUID()
        controlTask?.cancel()
        if isPlaying || self.isStartingPlayback || self.player.rate != 0 {
            self.isStartingPlayback = false
            self.dependencies.pause(self.player)
            self.refreshProgress()
            return
        }
        let request = self.controlGeneration, expectedLifecycle = self.lifecycle
        self.isStartingPlayback = true
        controlTask = Task { [weak self] in
            guard let self else { return }
            await self.lifetime.run { [self] in
            defer { if self.controlGeneration == request { self.isStartingPlayback = false } }
            self.refreshProgress()
            if self.duration > 0, self.elapsed >= self.duration - 0.05 {
                guard await self.dependencies.seek(self.player, .zero) else { return }
            }
            let activated = await self.session.activate()
            guard activated, self.isActive, self.lifecycle == expectedLifecycle,
                  self.controlGeneration == request, !Task.isCancelled else { return }
            self.dependencies.play(self.player)
            self.refreshProgress()
            }
        }
    }

    /// Scrubbing is preview-only and always leaves the clip paused.
    func seek(to seconds: Double) {
        guard self.isActive, !isSwitchingSource, seconds.isFinite, self.duration > 0 else { return }
        self.controlGeneration = UUID()
        controlTask?.cancel()
        self.isStartingPlayback = false
        self.dependencies.pause(self.player)
        isPlaying = false
        let target = min(max(seconds, 0), self.duration)
        self.elapsed = target
        let request = self.controlGeneration
        controlTask = Task { [weak self] in
            guard let self else { return }
            await self.lifetime.run { [self] in
            _ = await self.dependencies.seek(self.player, CMTime(seconds: target, preferredTimescale: 600))
            guard self.isActive, self.controlGeneration == request, !Task.isCancelled else { return }
            self.refreshProgress()
            }
        }
    }

    func pauseForEditing() {
        self.controlGeneration = UUID()
        controlTask?.cancel()
        self.isStartingPlayback = false
        self.dependencies.pause(self.player)
        self.refreshProgress()
    }

    func toggleMute() {
        isMuted.toggle()
        self.player.isMuted = isMuted
    }

    @discardableResult
    func toggleBoost() -> Task<Void, Never>? {
        guard self.isActive, canBoost, !isPreparing else { return nil }
        let enable = !isBoostEnabled
        let request = UUID()
        generation = request
        isPreparing = true
        hasBoostFailure = false
        preparationTask = Task { [weak self] in
            guard let self else { return }
            await self.lifetime.run { [self] in await self.changeSource(enable: enable, request: request) }
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
        lifetime.seal()
        Task { await lifetime.close() }
    }

    func close() async { await lifetime.close() }

    private func quiesce() {
        isActive = false
        lifecycle = UUID()
        cancelPreparation()
        dependencies.pause(player)
        player.currentItem?.cancelPendingSeeks()
        player.cancelPendingPrerolls()
        player.replaceCurrentItem(with: nil)
        session.cancelPendingActivation()
    }

    private func cancelPreparation() {
        controlGeneration = UUID()
        controlTask?.cancel()
        controlTask = nil
        isStartingPlayback = false
        isPlaying = false
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
                guard accepts(request) else { return }
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
