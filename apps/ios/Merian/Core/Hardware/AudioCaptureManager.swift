import AVFoundation
import Foundation

// MARK: - Error

enum AudioCaptureError: LocalizedError {
    case microphonePermissionDenied
    case hardwareSampleRateZero

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone access required. Check device settings."
        case .hardwareSampleRateZero:
            return "Audio hardware unavailable."
        }
    }
}

// MARK: - Manager

/// Observable Audio capture state and transition policy.
///
/// The focused recording and playback controllers own AVFoundation objects,
/// tasks, files, and audio-session leases behind this stable feature API.
@MainActor
@Observable
final class AudioCaptureManager {
    // MARK: Published state

    private(set) var isRecording = false
    private(set) var recordingProgress: Double = 0
    private(set) var spectrogramColumns: [SpectrogramColumn] = []
    private(set) var snrLevel: SNRLevel = .clear
    /// Non-nil after the user confirms in review, or after a max-duration recording auto-submits.
    /// Setting this triggers `onChange(of: audioFilePath)` in CaptureWorkspaceView → submitAudio.
    private(set) var audioFilePath: String?
    /// Non-nil after recording finishes, before the user confirms or discards.
    /// Drives the review state in AudioRecordingView.
    private(set) var pendingPlaybackPath: String?
    private(set) var isPlaying = false
    private(set) var isPaused = false
    private(set) var playbackProgress: Double = 0

    // MARK: Constants

    static let maxDuration: TimeInterval = 15
    // Full-clip buffer: ~42 ms / column × 360 ≈ 15 s of visible history
    static let columnCap = 360

    #if targetEnvironment(simulator)
    private static let preferredRecordSampleRate: Double? = 48_000
    #else
    private static let preferredRecordSampleRate: Double? = nil
    #endif

    // MARK: Private

    private static let snrHoldTickCount = 48
    private var pendingFileName: String?
    private var recordingTask: Task<Void, Never>?
    private var spectrogramHistory = CircularBuffer<SpectrogramColumn>(
        capacity: AudioCaptureManager.columnCap
    )
    private var snrHoldTicks = 0
    private var isStartingRecording = false
    private var resumeTask: Task<Void, Never>?
    private var transitionState = AudioCaptureTransitionState()
    private var autoSubmitOnMaxDuration = false
    private let maxDurationFeedback: @MainActor () -> Void
    private let recordingController: AudioRecordingEngineController
    private let playbackController: AudioReviewPlaybackController

    init(
        maxDurationFeedback: @escaping @MainActor () -> Void = {},
        dependencies: Dependencies = .live
    ) {
        self.maxDurationFeedback = maxDurationFeedback
        self.recordingController = AudioRecordingEngineController(
            dependencies: dependencies.recording
        )
        self.playbackController = AudioReviewPlaybackController(
            dependencies: dependencies.playback
        )
    }

    // MARK: - Recording

    /// Requests permission only from the explicit Record button action.
    func requestMicrophonePermissionForRecording() async throws {
        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else {
            throw AudioCaptureError.microphonePermissionDenied
        }
    }

    func startRecording(autoSubmitOnMaxDuration: Bool = false) async throws {
        guard !isRecording, !isStartingRecording else { return }
        isStartingRecording = true
        self.autoSubmitOnMaxDuration = autoSubmitOnMaxDuration
        defer { isStartingRecording = false }

        discardPending()

        // Permission prompts belong exclusively to the explicit action above.
        guard AVAudioApplication.shared.recordPermission == .granted else {
            self.autoSubmitOnMaxDuration = false
            throw AudioCaptureError.microphonePermissionDenied
        }
        if Task.isCancelled {
            self.autoSubmitOnMaxDuration = false
            return
        }

        reconcileCancelledRecordingFile(
            recordingController.cancelRecording()
        )
        cleanupPendingFile()
        let transition = transitionState.begin()

        do {
            pendingFileName = try await recordingController.start(
                preferredSampleRate: Self.preferredRecordSampleRate,
                onEvaluations: { [weak self] evaluations in
                    guard let self,
                          self.transitionState.isCurrent(transition) else {
                        return
                    }
                    self.apply(evaluations)
                }
            )
        } catch {
            handleCancelledOrFailedStartup()
            throw error
        }

        guard !Task.isCancelled,
              transitionState.isCurrent(transition) else {
            handleCancelledOrFailedStartup()
            throw CancellationError()
        }

        isRecording = true
        recordingProgress = 0
        scheduleRecordingCountdown(
            startingAfterTick: 0,
            transition: transition
        )
    }

    /// Stops early and always routes the partial clip to review.
    func stopRecordingEarly() {
        guard isRecording else { return }
        recordingTask?.cancel()
        recordingTask = nil
        finishRecording(reachedMaxDuration: false)
    }

    /// Pauses without discarding the installed tap or partial WAV.
    func pauseRecording() {
        guard isRecording, !isPaused else { return }
        invalidateRecordingTransitions()
        recordingTask?.cancel()
        recordingTask = nil
        recordingController.pause()
        isPaused = true
        snrLevel = .clear
        snrHoldTicks = 0
    }

    /// Resumes a paused recording and rebuilds the countdown from its progress.
    func resumeRecording() {
        guard isRecording,
              isPaused,
              resumeTask == nil else { return }

        let transition = transitionState.begin()
        resumeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.resumeTask = nil }

            do {
                try await self.recordingController.resume(
                    preferredSampleRate: Self.preferredRecordSampleRate
                )
            } catch {
                guard !Task.isCancelled,
                      self.transitionState.isCurrent(transition) else {
                    return
                }
                self.cancelRecording()
                return
            }

            guard !Task.isCancelled,
                  self.transitionState.isCurrent(transition),
                  self.isRecording,
                  self.isPaused else {
                self.recordingController.pause()
                return
            }

            self.isPaused = false
            let startTick = Int((self.recordingProgress * 100).rounded())
            guard startTick < 100 else {
                self.finishRecording(reachedMaxDuration: true)
                return
            }
            self.scheduleRecordingCountdown(
                startingAfterTick: startTick,
                transition: transition
            )
        }
    }

    /// Invalidates pending start/resume work without racing engine teardown.
    func cancelPendingRecordingTransition() {
        guard isStartingRecording || resumeTask != nil else { return }
        invalidateRecordingTransitions()
    }

    /// Cancels an active recording and discards all associated state.
    func cancelRecording() {
        let startupWasInProgress = isStartingRecording
        invalidateRecordingTransitions()
        recordingTask?.cancel()
        recordingTask = nil

        guard !startupWasInProgress else {
            isRecording = false
            isPaused = false
            recordingProgress = 0
            autoSubmitOnMaxDuration = false
            resetSpectrogramState()
            return
        }

        reconcileCancelledRecordingFile(
            recordingController.cancelRecording()
        )
        cleanupPendingFile()
        isRecording = false
        isPaused = false
        recordingProgress = 0
        autoSubmitOnMaxDuration = false
        discardPending()
    }

    /// Resets all state after submission or when leaving Audio entirely.
    func reset() {
        let startupWasInProgress = isStartingRecording
        invalidateRecordingTransitions()
        stopPlayback()
        recordingTask?.cancel()
        recordingTask = nil
        if !startupWasInProgress {
            reconcileCancelledRecordingFile(
                recordingController.cancelRecording()
            )
            cleanupPendingFile()
        }
        if let name = pendingPlaybackPath {
            deleteTemporaryFile(named: name)
        }
        isRecording = false
        isPaused = false
        recordingProgress = 0
        resetSpectrogramState()
        audioFilePath = nil
        pendingPlaybackPath = nil
        if !startupWasInProgress {
            pendingFileName = nil
        }
        autoSubmitOnMaxDuration = false
    }

    // MARK: - Review / Playback

    /// Plays the pending recording through the speaker.
    func playPendingRecording() {
        guard let path = pendingPlaybackPath, !isPlaying else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(path)
        let started = playbackController.start(
            fileURL: url,
            resumeProgress: playbackProgress,
            onProgress: { [weak self] progress in
                self?.playbackProgress = progress
            },
            onCompletion: { [weak self] in
                self?.isPlaying = false
                self?.playbackProgress = 0
            }
        )
        if started {
            isPlaying = true
        }
    }

    func stopPlayback() {
        playbackController.stop()
        isPlaying = false
        playbackProgress = 0
    }

    /// Seeks to a fractional position (0…1) before or during playback.
    func seekPlayback(to progress: Double) {
        let clamped = max(0, min(1, progress))
        playbackController.seek(to: clamped)
        playbackProgress = clamped
    }

    /// Moves from review to the established submission handoff.
    func confirmAndSubmit() {
        stopPlayback()
        audioFilePath = pendingPlaybackPath
        pendingPlaybackPath = nil
    }

    /// Restores a failed direct submission without deleting its recording.
    func restoreSubmissionForReview() {
        guard pendingPlaybackPath == nil,
              let submittedPath = audioFilePath else { return }
        pendingPlaybackPath = submittedPath
        audioFilePath = nil
    }

    /// Discards the pending review recording and returns to idle state.
    func discardPending() {
        stopPlayback()
        if let name = pendingPlaybackPath {
            deleteTemporaryFile(named: name)
            pendingPlaybackPath = nil
        }
        resetSpectrogramState()
    }

    // MARK: - Private

    private func scheduleRecordingCountdown(
        startingAfterTick startTick: Int,
        transition: AudioCaptureTransitionToken
    ) {
        guard startTick < 100 else { return }
        recordingTask?.cancel()
        recordingTask = Task { @MainActor [weak self] in
            for tick in (startTick + 1)...100 {
                do {
                    try await Task.sleep(nanoseconds: 150_000_000)
                } catch {
                    return
                }
                guard let self,
                      self.isRecording,
                      !self.isPaused,
                      self.transitionState.isCurrent(transition) else {
                    return
                }
                self.recordingProgress = Double(tick) / 100
            }

            guard let self,
                  self.isRecording,
                  !self.isPaused,
                  self.transitionState.isCurrent(transition) else {
                return
            }
            self.completeMaximumDurationRecording()
        }
    }

    private func invalidateRecordingTransitions() {
        transitionState.invalidate()
        resumeTask?.cancel()
        recordingController.invalidatePendingOperation()
    }

    private func apply(_ evaluations: [AudioRecordingColumnEvaluation]) {
        let severity: [SNRLevel: Int] = [
            .clear: 0,
            .caution: 1,
            .warning: 2,
            .clipping: 3
        ]
        for evaluation in evaluations {
            spectrogramHistory.append(evaluation.column)
            let currentSeverity = severity[snrLevel] ?? 0
            let newSeverity = severity[evaluation.snrLevel] ?? 0

            if newSeverity > currentSeverity {
                snrLevel = evaluation.snrLevel
                snrHoldTicks = Self.snrHoldTickCount
            } else if newSeverity == currentSeverity, newSeverity > 0 {
                snrHoldTicks = Self.snrHoldTickCount
            } else if snrHoldTicks > 0 {
                snrHoldTicks -= 1
            } else {
                snrLevel = evaluation.snrLevel
            }
        }
        spectrogramColumns = spectrogramHistory.elements
    }

    private func finishRecording(reachedMaxDuration: Bool) {
        invalidateRecordingTransitions()
        recordingTask?.cancel()
        let retainedFileName = recordingController.finishRecording()
        let completedFileName = retainedFileName ?? pendingFileName
        if reachedMaxDuration, autoSubmitOnMaxDuration {
            audioFilePath = completedFileName
        } else {
            pendingPlaybackPath = completedFileName
        }
        pendingFileName = nil
        isRecording = false
        isPaused = false
        recordingTask = nil
        autoSubmitOnMaxDuration = false
    }

    private func completeMaximumDurationRecording() {
        maxDurationFeedback()
        finishRecording(reachedMaxDuration: true)
    }

    private func reconcileCancelledRecordingFile(_ fileName: String?) {
        guard fileName == pendingFileName else { return }
        pendingFileName = nil
    }

    private func cleanupPendingFile() {
        guard let name = pendingFileName else { return }
        deleteTemporaryFile(named: name)
        pendingFileName = nil
    }

    private func deleteTemporaryFile(named fileName: String) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: url)
    }

    private func handleCancelledOrFailedStartup() {
        invalidateRecordingTransitions()
        reconcileCancelledRecordingFile(
            recordingController.cancelRecording()
        )
        cleanupPendingFile()
        isRecording = false
        isPaused = false
        recordingProgress = 0
        autoSubmitOnMaxDuration = false
        resetSpectrogramState()
    }

    private func resetSpectrogramState() {
        spectrogramHistory.removeAll()
        spectrogramColumns = []
        snrLevel = .clear
        snrHoldTicks = 0
        recordingController.resetAnalysis()
    }

    #if DEBUG
    func debugStageStartupState(
        fileName: String,
        dspTask: Task<Void, Never>? = nil
    ) {
        pendingFileName = fileName
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileName)
        recordingController.debugStageStartup(
            fileURL: fileURL,
            dspTask: dspTask
        )
    }

    func debugHandleCancelledStartup() {
        handleCancelledOrFailedStartup()
    }

    var debugHasDSPTask: Bool { recordingController.debugHasDSPTask }
    var debugPendingFileName: String? { pendingFileName }
    var debugHasAudioEngine: Bool {
        recordingController.debugHasActiveEngine
    }
    var debugHasResumeTask: Bool { resumeTask != nil }

    func debugStagePausedRecording(
        engine _: AVAudioEngine = AVAudioEngine(),
        progress: Double = 0
    ) {
        recordingController.debugStagePausedRecording()
        isRecording = true
        isPaused = true
        recordingProgress = progress
    }

    func debugStageRecordingForFinish(
        fileName: String,
        autoSubmitOnMaxDuration: Bool
    ) {
        pendingFileName = fileName
        isRecording = true
        self.autoSubmitOnMaxDuration = autoSubmitOnMaxDuration
    }

    func debugFinishRecording(reachedMaxDuration: Bool) {
        finishRecording(reachedMaxDuration: reachedMaxDuration)
    }

    func debugCompleteMaximumDurationRecording() {
        completeMaximumDurationRecording()
    }
    #endif
}
