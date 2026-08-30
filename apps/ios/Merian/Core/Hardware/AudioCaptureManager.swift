import AVFoundation
import Foundation

// MARK: - Error

enum AudioCaptureError: LocalizedError {
    case microphonePermissionDenied
    case hardwareSampleRateZero

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied: return "Microphone access required. Check device settings."
        case .hardwareSampleRateZero:     return "Audio hardware unavailable."
        }
    }
}

// MARK: - Manager

/// Off-main-thread AVAudioEngine recording with live spectrogram and ambient-noise feedback.
/// Mirrors the Task.detached AVAudioSession setup pattern from SpeechManager to prevent
/// MainActor IPC deadlock against mediaserverd.
@MainActor
@Observable
final class AudioCaptureManager {

    // MARK: Published state

    private(set) var isRecording: Bool = false
    private(set) var recordingProgress: Double = 0
    private(set) var spectrogramColumns: [SpectrogramColumn] = []
    private(set) var snrLevel: SNRLevel = .clear
    /// Non-nil after the user confirms in review, or after a max-duration recording auto-submits.
    /// Setting this triggers `onChange(of: audioFilePath)` in CaptureWorkspaceView → submitAudio.
    private(set) var audioFilePath: String?
    /// Non-nil after recording finishes, before the user confirms or discards.
    /// Drives the review state in AudioRecordingView.
    private(set) var pendingPlaybackPath: String?
    private(set) var isPlaying: Bool = false
    private(set) var isPaused: Bool = false
    private(set) var playbackProgress: Double = 0

    // MARK: Constants

    static let maxDuration: TimeInterval = 15
    // Full-clip buffer: ~42 ms / column × 360 ≈ 15 s of visible history
    static let columnCap = 360

    // MARK: Private

    /// Created only after a user-initiated recording request has received microphone
    /// authorization. In particular, lifecycle cleanup must not access `inputNode` on a
    /// fresh install because doing so can cause iOS to present the permission alert.
    private var audioEngine: AVAudioEngine?
    private let spectrogram = SpectrogramActor()
    private var pendingFileName: String?
    private var recordingTask: Task<Void, Never>?
    private var audioPlayer: AVAudioPlayer?
    private var playbackProgressTask: Task<Void, Never>?
    private var playbackCompletionTask: Task<Void, Never>?
    private var dspTask: Task<Void, Never>?
    private var spectrogramContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    private var spectrogramHistory = CircularBuffer<SpectrogramColumn>(capacity: AudioCaptureManager.columnCap)
    private var snrHoldTicks: Int = 0
    private var isStartingRecording: Bool = false
    private var startupSetupTask: Task<Void, Error>?
    private var resumeTask: Task<Void, Never>?
    private var transitionState = AudioCaptureTransitionState()
    private var audioSessionLease: AudioSessionCoordinator.Lease?
    private var autoSubmitOnMaxDuration: Bool = false
    private let maxDurationFeedback: @MainActor () -> Void
    private let dependencies: Dependencies
    private static let snrHoldTickCount = 48
    nonisolated private static let inputFormatRecoveryAttempts = 4
    nonisolated private static let inputFormatRecoveryDelayNanoseconds: UInt64 = 75_000_000

    #if targetEnvironment(simulator)
    private static let preferredRecordSampleRate: Double? = 48_000
    #else
    private static let preferredRecordSampleRate: Double? = nil
    #endif

    init(
        maxDurationFeedback: @escaping @MainActor () -> Void = {},
        dependencies: Dependencies = .live
    ) {
        self.maxDurationFeedback = maxDurationFeedback
        self.dependencies = dependencies
    }

    nonisolated private static func copyPCMBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameCapacity) else {
            return nil
        }
        copy.frameLength = buffer.frameLength

        let sourceBuffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        let destinationBuffers = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        guard sourceBuffers.count == destinationBuffers.count else { return nil }

        for index in 0..<sourceBuffers.count {
            let sourceBuffer = sourceBuffers[index]
            guard let sourceData = sourceBuffer.mData,
                  let destinationData = destinationBuffers[index].mData else {
                return nil
            }
            memcpy(destinationData, sourceData, Int(sourceBuffer.mDataByteSize))
            destinationBuffers[index].mDataByteSize = sourceBuffer.mDataByteSize
        }

        return copy
    }

    // MARK: - Recording

    /// Called directly from the Record section's red button so the system prompt is
    /// presented in the context of the user action, before any hardware handoff delay.
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
        defer {
            startupSetupTask = nil
            isStartingRecording = false
        }
        // Clear any leftover review state before a fresh recording session.
        discardPending()

        // Fail closed without prompting. Permission requests belong exclusively to the
        // explicit user-action method above.
        guard AVAudioApplication.shared.recordPermission == .granted else {
            self.autoSubmitOnMaxDuration = false
            throw AudioCaptureError.microphonePermissionDenied
        }
        if Task.isCancelled {
            self.autoSubmitOnMaxDuration = false
            return
        }

        teardownEngine()
        let transition = transitionState.begin()
        let engine = AVAudioEngine()
        audioEngine = engine

        let fileName = "\(UUID().uuidString).wav"
        pendingFileName = fileName
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        let actor = spectrogram
        let manager = self
        let dependencies = self.dependencies

        do {
            let setupTask = Task.detached { [manager] in
                let lease = try await dependencies.activateRecordingSession(
                    AudioCaptureManager.preferredRecordSampleRate
                )

                let acceptedLease = await MainActor.run {
                    guard manager.isCurrentRecordingTransition(
                        transition,
                        engine: engine
                    ) else {
                        return false
                    }
                    manager.audioSessionLease = lease
                    return true
                }
                guard acceptedLease else {
                    await dependencies.deactivateAudioSession(lease)
                    throw CancellationError()
                }
                try Task.checkCancellation()

                let inputNode = engine.inputNode
                var fmt = inputNode.outputFormat(forBus: 0)
                if fmt.sampleRate <= 0 || fmt.channelCount == 0 {
                    // AVFoundation can briefly expose a zero-rate input while the route is
                    // settling after another capture session releases the hardware. Give the
                    // activated recording route a small, bounded recovery window before
                    // reporting a genuine hardware failure.
                    for _ in 0..<AudioCaptureManager.inputFormatRecoveryAttempts {
                        try Task.checkCancellation()
                        try await Task.sleep(
                            nanoseconds: AudioCaptureManager.inputFormatRecoveryDelayNanoseconds
                        )
                        engine.reset()
                        fmt = inputNode.outputFormat(forBus: 0)
                        if fmt.sampleRate > 0 && fmt.channelCount > 0 { break }
                    }
                }
                guard fmt.sampleRate > 0, fmt.channelCount > 0 else {
                    throw AudioCaptureError.hardwareSampleRateZero
                }

                // Write canonical Int16 PCM WAV regardless of the hardware's native Float32
                // layout. AVAudioFile converts Float32→Int16 automatically on each write, and
                // Int16 PCM (audioFormat=1) is the one format the edge audio parsers handle
                // unconditionally — avoiding the WAVEFORMATEXTENSIBLE
                // (audioFormat=0xFFFE) WAV variant that non-interleaved Float32 can produce.
                guard let int16Fmt = AVAudioFormat(
                    commonFormat: .pcmFormatInt16,
                    sampleRate: fmt.sampleRate,
                    channels: fmt.channelCount,
                    interleaved: true
                ) else { throw AudioCaptureError.hardwareSampleRateZero }
                let file = try AVAudioFile(forWriting: fileURL, settings: int16Fmt.settings)

                let (stream, continuation) = AsyncStream.makeStream(
                    of: AVAudioPCMBuffer.self,
                    bufferingPolicy: .bufferingNewest(2)
                )

                let acceptedStream = await MainActor.run {
                    guard manager.isCurrentRecordingTransition(
                        transition,
                        engine: engine
                    ) else {
                        return false
                    }
                    manager.spectrogramContinuation = continuation
                    manager.dspTask?.cancel()
                    manager.dspTask = Task.detached { [weak manager] in
                        for await buffer in stream {
                            if Task.isCancelled { break }
                            let columns = await actor.processColumns(buffer: buffer)
                            guard !columns.isEmpty else { continue }

                            var columnEvaluations: [(column: SpectrogramColumn, snr: SNRLevel)] = []
                            columnEvaluations.reserveCapacity(columns.count)
                            for column in columns {
                                let snr = await actor.snrLevel(from: column)
                                columnEvaluations.append((column, snr))
                            }
                            let evaluatedColumns = columnEvaluations

                            await MainActor.run { [weak manager] in
                                guard let manager,
                                      manager.isCurrentRecordingTransition(
                                          transition,
                                          engine: engine
                                      ) else { return }
                                for evaluatedColumn in evaluatedColumns {
                                    manager.spectrogramHistory.append(evaluatedColumn.column)

                                    let severity: [SNRLevel: Int] = [.clear: 0, .caution: 1, .warning: 2, .clipping: 3]
                                    let currentSeverity = severity[manager.snrLevel] ?? 0
                                    let newSeverity = severity[evaluatedColumn.snr] ?? 0

                                    if newSeverity > currentSeverity {
                                        manager.snrLevel = evaluatedColumn.snr
                                        manager.snrHoldTicks = Self.snrHoldTickCount
                                    } else if newSeverity == currentSeverity && newSeverity > 0 {
                                        manager.snrHoldTicks = Self.snrHoldTickCount
                                    } else if manager.snrHoldTicks > 0 {
                                        manager.snrHoldTicks -= 1
                                    } else {
                                        manager.snrLevel = evaluatedColumn.snr
                                    }
                                }
                                manager.spectrogramColumns = manager.spectrogramHistory.elements
                            }
                        }
                    }
                    return true
                }
                guard acceptedStream else {
                    continuation.finish()
                    throw CancellationError()
                }

                // Defensive removal: prevents the crash if a tap is somehow still installed
                // (e.g. rapid start→stop→start before the async engine setup fully completes).
                inputNode.removeTap(onBus: 0)
                inputNode.installTap(onBus: 0, bufferSize: 4096, format: fmt) { buffer, _ in
                    // Sequential write from the audio thread — no concurrency hazard.
                    try? file.write(from: buffer)

                    // Yield to the bounded pipeline, dropping oldest if the spectrogram actor falls behind.
                    guard let retainedBuffer = AudioCaptureManager.copyPCMBuffer(buffer) else { return }
                    continuation.yield(retainedBuffer)
                }

                try Task.checkCancellation()
                engine.prepare()
                try dependencies.startEngine(engine)
            }
            startupSetupTask = setupTask
            try await withTaskCancellationHandler {
                try await setupTask.value
            } onCancel: {
                setupTask.cancel()
            }
        } catch {
            handleCancelledOrFailedStartup()
            throw error
        }

        guard !Task.isCancelled,
              isCurrentRecordingTransition(
                  transition,
                  engine: engine
              ) else {
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

    /// Stops the recording early and always routes the partial clip to review.
    func stopRecordingEarly() {
        guard isRecording else { return }
        recordingTask?.cancel()
        recordingTask = nil
        finishRecording(reachedMaxDuration: false)
    }

    /// Pauses an active recording without discarding audio. Engine tap stays installed.
    func pauseRecording() {
        guard isRecording, !isPaused, let audioEngine else { return }
        invalidateRecordingTransitions()
        recordingTask?.cancel()
        recordingTask = nil
        audioEngine.pause()
        isPaused = true
        snrLevel = .clear
        snrHoldTicks = 0
    }

    /// Resumes a paused recording, rebuilding the countdown from current progress.
    func resumeRecording() {
        guard isRecording,
              isPaused,
              resumeTask == nil,
              let audioEngine else { return }

        let transition = transitionState.begin()
        let dependencies = self.dependencies
        resumeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.resumeTask = nil }

            let lease: AudioSessionCoordinator.Lease
            do {
                lease = try await dependencies.activateRecordingSession(
                    Self.preferredRecordSampleRate
                )
            } catch {
                guard !Task.isCancelled,
                      self.isCurrentRecordingTransition(
                          transition,
                          engine: audioEngine
                      ) else { return }
                self.cancelRecording()
                return
            }

            guard !Task.isCancelled,
                  self.isCurrentRecordingTransition(
                      transition,
                      engine: audioEngine
                  ),
                  self.isRecording,
                  self.isPaused else {
                await dependencies.deactivateAudioSession(lease)
                return
            }

            self.audioSessionLease = lease
            do {
                try dependencies.startEngine(audioEngine)
            } catch {
                self.cancelRecording()
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

    /// Invalidates asynchronous start/resume work without touching an active
    /// engine. The owner of a pending startup performs teardown after its task
    /// exits, avoiding concurrent AVAudioEngine mutation.
    func cancelPendingRecordingTransition() {
        guard isStartingRecording || resumeTask != nil else { return }
        invalidateRecordingTransitions()
    }

    /// Cancels an active recording and discards all audio state including any pending review.
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

        teardownEngine()
        cleanupPendingFile()
        isRecording = false
        isPaused = false
        recordingProgress = 0
        autoSubmitOnMaxDuration = false
        discardPending()
    }

    /// Resets all state. Call after submission completes or when leaving audio mode entirely.
    func reset() {
        let startupWasInProgress = isStartingRecording
        invalidateRecordingTransitions()
        if !startupWasInProgress {
            stopPlayback()
        }
        recordingTask?.cancel()
        recordingTask = nil
        playbackCompletionTask?.cancel()
        playbackCompletionTask = nil
        if !startupWasInProgress {
            teardownEngine()
            cleanupPendingFile()
        }
        if let name = pendingPlaybackPath {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: url)
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
        Task { await spectrogram.reset() }
    }

    // MARK: - Review / Playback

    /// Plays the pending recording through the speaker. Auto-clears `isPlaying` at end-of-file.
    /// Session activation is serialized through `AudioSessionCoordinator` so a stale stop path
    /// cannot deactivate a newer playback or recording session.
    func playPendingRecording() {
        guard let path = pendingPlaybackPath, !isPlaying else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(path)
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return }
        audioPlayer = player
        isPlaying = true
        // Preserve scrubbed position so playback resumes from where the user left the playhead.
        let resumeProgress = playbackProgress

        let capturedPlayer = player

        // Poll currentTime at ~30 fps to drive the scrub line.
        playbackProgressTask?.cancel()
        playbackCompletionTask?.cancel()
        playbackProgressTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 33_000_000)
                guard let self, self.audioPlayer === capturedPlayer else { return }
                let p = capturedPlayer.duration > 0 ? capturedPlayer.currentTime / capturedPlayer.duration : 0
                self.playbackProgress = min(1, max(0, p))
            }
        }

        playbackCompletionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let lease = try? await AudioSessionCoordinator.shared.activate(.playback)
            guard let lease else {
                if self.audioPlayer === capturedPlayer {
                    self.stopPlayback()
                }
                return
            }

            guard !Task.isCancelled else {
                await AudioSessionCoordinator.shared.deactivate(ifCurrent: lease)
                return
            }

            self.audioSessionLease = lease
            guard self.audioPlayer === capturedPlayer else {
                self.releaseAudioSessionLease()
                return
            }

            if resumeProgress > 0 {
                capturedPlayer.currentTime = capturedPlayer.duration * resumeProgress
            }
            _ = capturedPlayer.play()

            let duration = capturedPlayer.duration
            let remaining = max(0, duration * (1 - resumeProgress))
            try? await Task.sleep(nanoseconds: UInt64((remaining + 0.3) * 1_000_000_000))
            guard !Task.isCancelled else { return }

            if self.audioPlayer === capturedPlayer {
                self.playbackProgressTask?.cancel()
                self.playbackProgressTask = nil
                self.isPlaying = false
                self.audioPlayer = nil
                self.playbackProgress = 0
                self.playbackCompletionTask = nil
                self.releaseAudioSessionLease()
            }
        }
    }

    func stopPlayback() {
        playbackCompletionTask?.cancel()
        playbackCompletionTask = nil
        playbackProgressTask?.cancel()
        playbackProgressTask = nil
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        playbackProgress = 0
        releaseAudioSessionLease()
    }

    /// Seeks playback to a fractional position (0…1). Works while playing or paused.
    func seekPlayback(to progress: Double) {
        let clamped = max(0, min(1, progress))
        if let player = audioPlayer {
            player.currentTime = player.duration * clamped
        }
        playbackProgress = clamped
    }

    /// Moves from review → submission by setting `audioFilePath`.
    /// The `onChange(of: audioFilePath)` in CaptureWorkspaceView picks this up and calls submitAudio.
    func confirmAndSubmit() {
        stopPlayback()
        audioFilePath = pendingPlaybackPath
        pendingPlaybackPath = nil
    }

    /// Returns a failed direct submission to the review state without deleting
    /// the irreplaceable recording. Setting `audioFilePath` back to nil does not
    /// retrigger submission; the next explicit confirm creates a fresh change.
    func restoreSubmissionForReview() {
        guard pendingPlaybackPath == nil,
              let submittedPath = audioFilePath else { return }
        pendingPlaybackPath = submittedPath
        audioFilePath = nil
    }

    /// Discards the pending recording and returns to idle state without submitting.
    func discardPending() {
        stopPlayback()
        if let name = pendingPlaybackPath {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: url)
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
                self.recordingProgress = Double(tick) / 100.0
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

    private func isCurrentRecordingTransition(
        _ transition: AudioCaptureTransitionToken,
        engine: AVAudioEngine
    ) -> Bool {
        transitionState.isCurrent(transition)
            && audioEngine === engine
    }

    private func invalidateRecordingTransitions() {
        transitionState.invalidate()
        startupSetupTask?.cancel()
        resumeTask?.cancel()
    }

    private func finishRecording(reachedMaxDuration: Bool) {
        invalidateRecordingTransitions()
        recordingTask?.cancel()
        teardownEngine()
        if reachedMaxDuration, autoSubmitOnMaxDuration {
            audioFilePath = pendingFileName
        } else {
            // Route through the review state instead of firing submission directly.
            pendingPlaybackPath = pendingFileName
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

    private func teardownEngine() {
        spectrogramContinuation?.finish()
        spectrogramContinuation = nil
        if let audioEngine {
            // Remove tap before stopping — prevents the audio thread from writing into a
            // stopped engine and avoids AVAudioEngine assertion failures on some iOS builds.
            // The optional also ensures fresh-install cleanup never initializes inputNode.
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
            self.audioEngine = nil
        }
        dspTask?.cancel()
        dspTask = nil
        releaseAudioSessionLease()
    }

    private func releaseAudioSessionLease() {
        let lease = audioSessionLease
        audioSessionLease = nil
        let deactivateAudioSession =
            dependencies.deactivateAudioSession
        Task {
            await deactivateAudioSession(lease)
        }
    }

    private func cleanupPendingFile() {
        guard let name = pendingFileName else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: url)
        pendingFileName = nil
    }

    private func handleCancelledOrFailedStartup() {
        invalidateRecordingTransitions()
        teardownEngine()
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
        Task { await spectrogram.reset() }
    }

#if DEBUG
    func debugStageStartupState(fileName: String, dspTask: Task<Void, Never>? = nil) {
        pendingFileName = fileName
        self.dspTask = dspTask
    }

    func debugHandleCancelledStartup() {
        handleCancelledOrFailedStartup()
    }

    var debugHasDSPTask: Bool { dspTask != nil }
    var debugPendingFileName: String? { pendingFileName }
    var debugHasAudioEngine: Bool { audioEngine != nil }
    var debugHasResumeTask: Bool { resumeTask != nil }

    func debugStagePausedRecording(
        engine: AVAudioEngine = AVAudioEngine(),
        progress: Double = 0
    ) {
        audioEngine = engine
        isRecording = true
        isPaused = true
        recordingProgress = progress
    }

    func debugStageRecordingForFinish(fileName: String, autoSubmitOnMaxDuration: Bool) {
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
