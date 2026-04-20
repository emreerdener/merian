import AVFoundation
import Foundation

// MARK: - Error

enum AudioCaptureError: LocalizedError {
    case microphonePermissionDenied
    case hardwareSampleRateZero

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied: return "Microphone access required. Check Settings."
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
    /// Non-nil only after the user explicitly confirms in the review UI.
    /// Setting this triggers `onChange(of: audioFilePath)` in CaptureWorkspaceView → submitAudio.
    private(set) var audioFilePath: String?
    /// Non-nil after recording finishes, before the user confirms or discards.
    /// Drives the review state in AudioRecordingView.
    private(set) var pendingPlaybackPath: String?
    private(set) var isPlaying: Bool = false
    private(set) var isPaused: Bool = false

    // MARK: Constants

    static let maxDuration: TimeInterval = 12
    // Rolling display buffer: ~85 ms / column × 120 ≈ 10 s of visible history
    static let columnCap = 120

    // MARK: Private

    private let audioEngine = AVAudioEngine()
    private let spectrogram = SpectrogramActor()
    private var pendingFileName: String?
    private var recordingTask: Task<Void, Never>?
    private var audioPlayer: AVAudioPlayer?

    // MARK: - Recording

    func startRecording() async throws {
        guard !isRecording else { return }
        // Clear any leftover review state before a fresh recording session.
        discardPending()

        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else { throw AudioCaptureError.microphonePermissionDenied }
        if Task.isCancelled { return }

        teardownEngine()

        let fileName = "\(UUID().uuidString).wav"
        pendingFileName = fileName
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        let engine = audioEngine
        let actor = spectrogram
        let manager = self

        try await Task.detached { [manager] in
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)

            #if targetEnvironment(simulator)
            try? session.setPreferredSampleRate(48000)
            #endif

            try session.setActive(true)

            let inputNode = engine.inputNode
            let fmt = inputNode.outputFormat(forBus: 0)
            guard fmt.sampleRate > 0 else { throw AudioCaptureError.hardwareSampleRateZero }

            // AVAudioFile is captured by the tap closure; closes when the tap is removed.
            let file = try AVAudioFile(forWriting: fileURL, settings: fmt.settings)

            inputNode.installTap(onBus: 0, bufferSize: 4096, format: fmt) { buffer, _ in
                // Sequential write from the audio thread — no concurrency hazard.
                try? file.write(from: buffer)

                // DSP is actor-isolated; spawn a detached task so the audio thread never blocks.
                Task.detached {
                    guard let col = await actor.process(buffer: buffer) else { return }
                    let snr = await actor.snrLevel(from: col)
                    // [weak manager] breaks the retain cycle:
                    // AudioCaptureManager → audioEngine → inputNode → tap → manager (strong)
                    Task { @MainActor [weak manager] in
                        guard let manager else { return }
                        manager.spectrogramColumns.append(col)
                        if manager.spectrogramColumns.count > AudioCaptureManager.columnCap {
                            manager.spectrogramColumns.removeFirst()
                        }
                        manager.snrLevel = snr
                    }
                }
            }

            engine.prepare()
            try engine.start()
        }.value

        if Task.isCancelled {
            Task.detached {
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
            cleanupPendingFile()
            return
        }

        isRecording = true
        recordingProgress = 0

        // 100 ticks × 0.12 s = 12 s countdown
        recordingTask = Task { [weak self] in
            for i in 1...100 {
                try? await Task.sleep(nanoseconds: 120_000_000)
                if Task.isCancelled { return }
                await MainActor.run { self?.recordingProgress = Double(i) / 100.0 }
            }
            await MainActor.run { self?.finishRecording() }
        }
    }

    /// Pauses an active recording without discarding audio. Engine tap stays installed.
    func pauseRecording() {
        guard isRecording, !isPaused else { return }
        recordingTask?.cancel()
        recordingTask = nil
        audioEngine.pause()
        isPaused = true
    }

    /// Resumes a paused recording, rebuilding the countdown from current progress.
    func resumeRecording() {
        guard isRecording, isPaused else { return }
        Task {
            await Task.detached {
                try? AVAudioSession.sharedInstance().setActive(true)
            }.value
            do {
                try audioEngine.start()
            } catch {
                cancelRecording()
                return
            }
            isPaused = false
            let startTick = Int((recordingProgress * 100).rounded())
            guard startTick < 100 else { finishRecording(); return }
            recordingTask = Task { [weak self] in
                for i in (startTick + 1)...100 {
                    try? await Task.sleep(nanoseconds: 120_000_000)
                    if Task.isCancelled { return }
                    await MainActor.run { self?.recordingProgress = Double(i) / 100.0 }
                }
                await MainActor.run { self?.finishRecording() }
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
        discardPending()
    }

    /// Resets all state. Call after submission completes or when leaving audio mode entirely.
    func reset() {
        stopPlayback()
        recordingTask?.cancel()
        recordingTask = nil
        isRecording = false
        isPaused = false
        recordingProgress = 0
        spectrogramColumns = []
        snrLevel = .clear
        audioFilePath = nil
        pendingPlaybackPath = nil
        pendingFileName = nil
        Task { await spectrogram.reset() }
    }

    // MARK: - Review / Playback

    /// Plays the pending recording through the speaker. Auto-clears `isPlaying` at end-of-file.
    /// Uses Task.detached to activate the playback AVAudioSession off MainActor,
    /// mirroring the pattern used for recording setup.
    func playPendingRecording() {
        guard let path = pendingPlaybackPath, !isPlaying else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(path)
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return }
        audioPlayer = player
        isPlaying = true

        let capturedPlayer = player
        Task.detached { [weak self] in
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .default)
            try? session.setActive(true)
            await MainActor.run { _ = capturedPlayer.play() }

            let duration = capturedPlayer.duration
            try? await Task.sleep(nanoseconds: UInt64((duration + 0.3) * 1_000_000_000))
            // Reference equality guards against a stop → re-play race:
            // if the user stopped and started a new playback, audioPlayer is a different instance.
            await MainActor.run { [weak self] in
                guard let self, self.audioPlayer === capturedPlayer else { return }
                self.isPlaying = false
                self.audioPlayer = nil
            }
        }
    }

    func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
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
        guard let name = pendingPlaybackPath else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: url)
        pendingPlaybackPath = nil
        spectrogramColumns = []
        snrLevel = .clear
    }

    // MARK: - Private

    private func finishRecording() {
        teardownEngine()
        // Route through the review state instead of firing submission directly.
        // The user must explicitly confirm via the review UI before audioFilePath is set.
        pendingPlaybackPath = pendingFileName
        pendingFileName = nil
        isRecording = false
        isPaused = false
        recordingTask = nil
    }

    private func teardownEngine() {
        // Remove tap before stopping — prevents the audio thread from writing into a
        // stopped engine and avoids AVAudioEngine assertion failures on some iOS builds.
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        // Deactivate asynchronously to prevent mediaserverd IPC from blocking MainActor.
        Task.detached {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private func cleanupPendingFile() {
        guard let name = pendingFileName else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: url)
        pendingFileName = nil
    }
}
