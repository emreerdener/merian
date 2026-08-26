import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class ExplorePublicMediaPlaybackState {
    private(set) var player: AVPlayer?
    let playerID = UUID().uuidString
    private(set) var configuredMediaURL: String?
    private(set) var videoSurfaceGeneration = 0
    private(set) var pendingRecoverySeekTime: CMTime?

    private let observation = MediaPlaybackObservation()

    private(set) var audioPlaybackProgress = 0.0
    private(set) var audioElapsedSeconds = 0.0
    private(set) var audioDurationSeconds = 0.0
    private(set) var isPlayerItemReady = false
    private(set) var overlayState = ExploreVideoPlaybackOverlayState()
    private var resumeIntentState = ExploreVideoPlaybackResumeIntentState()
    private(set) var hasTrackedAudioPlaybackStart = false
    private(set) var hasActivatedAudioPlaybackSession = false
    private(set) var boostedAudioURL: URL?
    private(set) var isPreparingAudioBoost = false
    private(set) var isRevertingAudioBoost = false
    private(set) var audioBoostPreparationFailed = false
    private(set) var showsAudioBoostPreparationStatus = false
    private(set) var isAudioSeeking = false
    private var audioSeekWasPlaying = false

    @ObservationIgnored
    private var playbackControlFadeTask: Task<Void, Never>?
    @ObservationIgnored
    private var playbackRecoveryWatchdogTask: Task<Void, Never>?
    @ObservationIgnored
    private var unexpectedPauseRecoveryTask: Task<Void, Never>?

    var observedTimeControlStatus: AVPlayer.TimeControlStatus {
        observation.timeControlStatus
    }

    var observedItemStatus: AVPlayerItem.Status {
        observation.itemStatus
    }

    var observedEventSequence: UInt64 {
        observation.eventSequence
    }

    var observedCurrentTimeSeconds: Double {
        observation.currentTimeSeconds
    }

    var observedDurationSeconds: Double {
        observation.durationSeconds
    }

    var lastPlaybackEvent: MediaPlaybackLifecycleEvent? {
        observation.lastEvent
    }

    func isObserving(_ player: AVPlayer) -> Bool {
        observation.isObserving(player)
    }

    func installPlayer(_ player: AVPlayer, configuredMediaURL: String) {
        self.player = player
        self.configuredMediaURL = configuredMediaURL
        observation.observe(
            player,
            periodicInterval: CMTime(seconds: 0.1, preferredTimescale: 600)
        )
    }

    func resetPlayerState() {
        player?.pause()
        cancelPlaybackRecoveryWatchdog()
        cancelUnexpectedPauseRecovery()
        cancelPlaybackControlFade()
        observation.detach()
        isPlayerItemReady = false
        resetAudioPosition()
        configuredMediaURL = nil
        player = nil
    }

    func incrementVideoSurfaceGeneration() {
        videoSurfaceGeneration += 1
    }

    func setPendingRecoverySeekTime(_ time: CMTime?) {
        pendingRecoverySeekTime = time
    }

    func preservePendingRecoverySeekTime(_ time: CMTime?) {
        guard pendingRecoverySeekTime == nil else { return }
        pendingRecoverySeekTime = time
    }

    func setPlayerItemReady(_ isReady: Bool) {
        isPlayerItemReady = isReady
    }

    func reduceOverlay(_ event: ExploreVideoPlaybackOverlayState.Event) {
        overlayState.reduce(event)
    }

    func markSystemInterruption(shouldResume: Bool) {
        resumeIntentState.markSystemInterruption(shouldResume: shouldResume)
    }

    func consumeSystemResumeIntent() -> Bool {
        resumeIntentState.consumeSystemResumeIntent()
    }

    func clearResumeIntent() {
        resumeIntentState.clear()
    }

    func markAudioPlaybackStartedIfNeeded() -> Bool {
        guard !hasTrackedAudioPlaybackStart else { return false }
        hasTrackedAudioPlaybackStart = true
        return true
    }

    func markAudioPlaybackSessionActive() {
        hasActivatedAudioPlaybackSession = true
    }

    func markAudioPlaybackSessionInactive() {
        hasActivatedAudioPlaybackSession = false
    }

    func beginAudioSeek(wasPlaying: Bool) {
        isAudioSeeking = true
        audioSeekWasPlaying = wasPlaying
    }

    func finishAudioSeek() -> Bool {
        let shouldResume = audioSeekWasPlaying
        isAudioSeeking = false
        audioSeekWasPlaying = false
        return shouldResume
    }

    func setAudioPosition(progress: Double, elapsedSeconds: Double) {
        audioPlaybackProgress = progress
        audioElapsedSeconds = elapsedSeconds
    }

    func updateAudioPosition(elapsedSeconds: Double, durationSeconds: Double) {
        audioPlaybackProgress = max(0, min(1, elapsedSeconds / durationSeconds))
        audioElapsedSeconds = max(0, elapsedSeconds)
        audioDurationSeconds = durationSeconds
    }

    func resetAudioPosition() {
        audioPlaybackProgress = 0
        audioElapsedSeconds = 0
        audioDurationSeconds = 0
    }

    func setAudioBoostReverting(_ isReverting: Bool) {
        isRevertingAudioBoost = isReverting
    }

    func beginAudioBoostPreparation(showsStatus: Bool) {
        isPreparingAudioBoost = true
        showsAudioBoostPreparationStatus = showsStatus
        audioBoostPreparationFailed = false
    }

    func finishAudioBoostPreparation() {
        isPreparingAudioBoost = false
        showsAudioBoostPreparationStatus = false
    }

    func setBoostedAudioURL(_ url: URL?) {
        boostedAudioURL = url
    }

    func setAudioBoostPreparationFailed(_ didFail: Bool) {
        audioBoostPreparationFailed = didFail
    }

    func clearAudioBoostFeedback() {
        showsAudioBoostPreparationStatus = false
        audioBoostPreparationFailed = false
    }

    func replacePlaybackControlFadeTask(_ task: Task<Void, Never>?) {
        playbackControlFadeTask?.cancel()
        playbackControlFadeTask = task
    }

    func cancelPlaybackControlFade() {
        playbackControlFadeTask?.cancel()
        playbackControlFadeTask = nil
    }

    func clearPlaybackControlFadeTask() {
        playbackControlFadeTask = nil
    }

    func replacePlaybackRecoveryWatchdogTask(_ task: Task<Void, Never>?) {
        playbackRecoveryWatchdogTask?.cancel()
        playbackRecoveryWatchdogTask = task
    }

    func cancelPlaybackRecoveryWatchdog() {
        playbackRecoveryWatchdogTask?.cancel()
        playbackRecoveryWatchdogTask = nil
    }

    func clearPlaybackRecoveryWatchdogTask() {
        playbackRecoveryWatchdogTask = nil
    }

    func replaceUnexpectedPauseRecoveryTask(_ task: Task<Void, Never>?) {
        unexpectedPauseRecoveryTask?.cancel()
        unexpectedPauseRecoveryTask = task
    }

    func cancelUnexpectedPauseRecovery() {
        unexpectedPauseRecoveryTask?.cancel()
        unexpectedPauseRecoveryTask = nil
    }

    func clearUnexpectedPauseRecoveryTask() {
        unexpectedPauseRecoveryTask = nil
    }
}
