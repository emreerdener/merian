import AVFoundation
import Foundation

// MARK: - Error

actor AudioSessionCoordinator {
    enum Configuration: Sendable {
        case recordMeasurement(preferredSampleRate: Double?)
        case playback
    }

    struct Lease: Sendable {
        fileprivate let token: UInt64
    }

    static let shared = AudioSessionCoordinator()

    private var activeToken: UInt64 = 0

    func activate(_ configuration: Configuration) throws -> Lease {
        activeToken &+= 1
        let lease = Lease(token: activeToken)
        let session = AVAudioSession.sharedInstance()

        switch configuration {
        case .recordMeasurement(let preferredSampleRate):
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            if let preferredSampleRate {
                try? session.setPreferredSampleRate(preferredSampleRate)
            }
        case .playback:
            try session.setCategory(.playback, mode: .default)
        }

        try session.setActive(true)
        return lease
    }

    func deactivate(ifCurrent lease: Lease?) {
        guard let lease, lease.token == activeToken else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

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

/// Off-main-thread AVAudioEngine recording with live spectrogram and SNR feedback.
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
    // Full-clip buffer: ~85 ms / column × 180 ≈ 15 s of visible history
    static let columnCap = 180

    // MARK: Private

    private let audioEngine = AVAudioEngine()
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
    private var audioSessionLease: AudioSessionCoordinator.Lease?
    private var autoSubmitOnMaxDuration: Bool = false

    #if targetEnvironment(simulator)
    private static let preferredRecordSampleRate: Double? = 48_000
    #else
    private static let preferredRecordSampleRate: Double? = nil
    #endif

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

    func startRecording(autoSubmitOnMaxDuration: Bool = false) async throws {
        guard !isRecording, !isStartingRecording else { return }
        isStartingRecording = true
        self.autoSubmitOnMaxDuration = autoSubmitOnMaxDuration
        defer { isStartingRecording = false }
        // Clear any leftover review state before a fresh recording session.
        discardPending()

        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else {
            self.autoSubmitOnMaxDuration = false
            throw AudioCaptureError.microphonePermissionDenied
        }
        if Task.isCancelled {
            self.autoSubmitOnMaxDuration = false
            return
        }

        teardownEngine()

        let fileName = "\(UUID().uuidString).wav"
        pendingFileName = fileName
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        let engine = audioEngine
        let actor = spectrogram
        let manager = self

        do {
            try await Task.detached { [manager] in
                let lease = try await AudioSessionCoordinator.shared.activate(
                    .recordMeasurement(preferredSampleRate: AudioCaptureManager.preferredRecordSampleRate)
                )
                await MainActor.run { [weak manager] in
                    manager?.audioSessionLease = lease
                }

                let inputNode = engine.inputNode
                let fmt = inputNode.outputFormat(forBus: 0)
                guard fmt.sampleRate > 0 else { throw AudioCaptureError.hardwareSampleRateZero }

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

                await MainActor.run { [weak manager] in
                    manager?.spectrogramContinuation = continuation
                    manager?.dspTask?.cancel()
                    manager?.dspTask = Task.detached { [weak manager] in
                        for await buffer in stream {
                            if Task.isCancelled { break }
                            guard let col = await actor.process(buffer: buffer) else { continue }
                            let snr = await actor.snrLevel(from: col)

                            await MainActor.run { [weak manager] in
                                guard let manager else { return }
                                manager.spectrogramHistory.append(col)
                                manager.spectrogramColumns = manager.spectrogramHistory.elements

                                let severity: [SNRLevel: Int] = [.clear: 0, .caution: 1, .warning: 2, .clipping: 3]
                                let currentSeverity = severity[manager.snrLevel] ?? 0
                                let newSeverity = severity[snr] ?? 0

                                if newSeverity > currentSeverity {
                                    manager.snrLevel = snr
                                    manager.snrHoldTicks = 24 // ~2 seconds at ~85ms per buffer slice
                                } else if newSeverity == currentSeverity && newSeverity > 0 {
                                    manager.snrHoldTicks = 24
                                } else if manager.snrHoldTicks > 0 {
                                    manager.snrHoldTicks -= 1
                                } else {
                                    manager.snrLevel = snr
                                }
                            }
                        }
                    }
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

                engine.prepare()
                try engine.start()
            }.value
        } catch {
            handleCancelledOrFailedStartup()
            throw error
        }

        if Task.isCancelled {
            handleCancelledOrFailedStartup()
            return
        }

        isRecording = true
        recordingProgress = 0

        // 100 ticks × 0.15 s = 15 s countdown
        recordingTask = Task { [weak self] in
            for i in 1...100 {
                try? await Task.sleep(nanoseconds: 150_000_000)
                if Task.isCancelled { return }
                await MainActor.run { self?.recordingProgress = Double(i) / 100.0 }
            }
            await MainActor.run { 
                HapticManager.shared.triggerHeavyImpact()
                self?.finishRecording(reachedMaxDuration: true)
            }
        }
    }

    /// Stops the recording early and routes directly to review state, same as timer completion.
    func stopRecordingEarly() {
        guard isRecording else { return }
        recordingTask?.cancel()
        recordingTask = nil
        finishRecording(reachedMaxDuration: false)
    }

    /// Pauses an active recording without discarding audio. Engine tap stays installed.
    func pauseRecording() {
        guard isRecording, !isPaused else { return }
        recordingTask?.cancel()
        recordingTask = nil
        audioEngine.pause()
        isPaused = true
        snrLevel = .clear
        snrHoldTicks = 0
    }

    /// Resumes a paused recording, rebuilding the countdown from current progress.
    func resumeRecording() {
        guard isRecording, isPaused else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                let lease = try await AudioSessionCoordinator.shared.activate(
                    .recordMeasurement(preferredSampleRate: Self.preferredRecordSampleRate)
                )
                self.audioSessionLease = lease
                try audioEngine.start()
            } catch {
                cancelRecording()
                return
            }
            isPaused = false
            let startTick = Int((recordingProgress * 100).rounded())
            guard startTick < 100 else {
                finishRecording(reachedMaxDuration: true)
                return
            }
            recordingTask = Task { [weak self] in
                for i in (startTick + 1)...100 {
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    if Task.isCancelled { return }
                    await MainActor.run { self?.recordingProgress = Double(i) / 100.0 }
                }
                await MainActor.run { 
                    HapticManager.shared.triggerHeavyImpact()
                    self?.finishRecording(reachedMaxDuration: true)
                }
            }
        }
    }

    /// Cancels an active recording and discards all audio state including any pending review.
    func cancelRecording() {
        recordingTask?.cancel()
        recordingTask = nil
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
        stopPlayback()
        recordingTask?.cancel()
        recordingTask = nil
        playbackCompletionTask?.cancel()
        playbackCompletionTask = nil
        teardownEngine()
        cleanupPendingFile()
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
        pendingFileName = nil
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

    private func finishRecording(reachedMaxDuration: Bool) {
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

    private func teardownEngine() {
        spectrogramContinuation?.finish()
        spectrogramContinuation = nil
        // Remove tap before stopping — prevents the audio thread from writing into a
        // stopped engine and avoids AVAudioEngine assertion failures on some iOS builds.
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        dspTask?.cancel()
        dspTask = nil
        releaseAudioSessionLease()
    }

    private func releaseAudioSessionLease() {
        let lease = audioSessionLease
        audioSessionLease = nil
        Task {
            await AudioSessionCoordinator.shared.deactivate(ifCurrent: lease)
        }
    }

    private func cleanupPendingFile() {
        guard let name = pendingFileName else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: url)
        pendingFileName = nil
    }

    private func handleCancelledOrFailedStartup() {
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

    func debugStageRecordingForFinish(fileName: String, autoSubmitOnMaxDuration: Bool) {
        pendingFileName = fileName
        isRecording = true
        self.autoSubmitOnMaxDuration = autoSubmitOnMaxDuration
    }

    func debugFinishRecording(reachedMaxDuration: Bool) {
        finishRecording(reachedMaxDuration: reachedMaxDuration)
    }
#endif
}
