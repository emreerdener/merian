import AVFoundation
import Foundation
import Speech

struct PermissionError: LocalizedError {
    var errorDescription: String? {
        return "Microphone access required. Check device settings."
    }
}

struct DictationUnavailableError: LocalizedError {
    var errorDescription: String? {
        return "Dictation is temporarily unavailable. Please try again."
    }
}

@MainActor
@Observable
final class SpeechManager {
    var isRecording: Bool = false
    var isStarting: Bool = false
    var audioLevel: CGFloat = 0.0
    
    /// Lazily created after an explicit dictation action receives microphone permission.
    /// Calling stop/cleanup before first use must not initialize the system audio input.
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioSessionLease: AudioSessionCoordinator.Lease?
    private var sessionID: UUID?
    private var isConfiguringEngine = false
    private var hasInputTap = false
    private var releaseTask: Task<Void, Never>?
    private var finalization: CheckedContinuation<Bool, Never>?
    private var finalizationTimeout: Task<Void, Never>?

    #if targetEnvironment(simulator)
    private static let preferredRecordSampleRate: Double? = 48_000
    #else
    private static let preferredRecordSampleRate: Double? = nil
    #endif

    func startDictation(onResult: @MainActor @escaping (String) -> Void) async throws {
        guard !isStarting, !isRecording else { return }
        isStarting = true
        let id = UUID()
        sessionID = id
        defer {
            isStarting = false
            if !isRecording, sessionID == id { stopDictation() }
        }

        if let releaseTask { await releaseTask.value }
        try requireCurrentSession(id)

        // Ask first so the microphone prompt remains directly attached to the user's
        // dictation-button tap rather than appearing after speech-service startup delay.
        let micStatus = await AVAudioApplication.requestRecordPermission()
        guard micStatus else {
            throw PermissionError()
        }

        try requireCurrentSession(id)

        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard speechStatus == .authorized else {
            throw PermissionError()
        }
        
        try requireCurrentSession(id)

        guard let recognizer = await availableSpeechRecognizer() else {
            throw DictationUnavailableError()
        }
        
        try requireCurrentSession(id)
        
        teardownAudioEngine()
        let engine = AVAudioEngine()
        audioEngine = engine
        
        // on the iOS Simulator's HALC_ShellPlugIn.
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request
        let manager = self
        isConfiguringEngine = true
        
        do {
            try await Task.detached { [manager] in
                let lease = try await AudioSessionCoordinator.shared.activate(
                    .recordMeasurement(preferredSampleRate: SpeechManager.preferredRecordSampleRate)
                )
                await MainActor.run {
                    manager.audioSessionLease = lease
                }
                
                // Accessing inputNode for the first time negotiates hardware and triggers IPC.
                // MUST be detached so the Main Thread is yielded and free to receive mediaserverd callbacks.
                let inputNode = engine.inputNode
                let recordingFormat = inputNode.outputFormat(forBus: 0)
                guard recordingFormat.sampleRate > 0 else {
                    throw PermissionError() // HAL returned 0 Hz, bail.
                }
                
                inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                    request.append(buffer)
                    
                    guard let channelData = buffer.floatChannelData?[0] else { return }
                    let frames = buffer.frameLength
                    var rms: Float = 0
                    for i in 0..<Int(frames) {
                        rms += channelData[i] * channelData[i]
                    }
                    if frames > 0 {
                        rms = sqrt(rms / Float(frames))
                    }
                    
                    // Convert to a 0.0 - 1.0 scale
                    let minDb: Float = -60.0
                    let db = 20 * log10(max(rms, 1e-6))
                    let level = CGFloat(max(0.0, min(1.0, (db - minDb) / (0 - minDb))))
                    
                    Task { @MainActor in
                        guard manager.sessionID == id else { return }
                        manager.audioLevel = level
                    }
                }
                
                await MainActor.run { manager.hasInputTap = true }
                engine.prepare()
                try engine.start()
            }.value
            isConfiguringEngine = false
        } catch {
            // Configuration has joined before cancellation touches the engine.
            isConfiguringEngine = false
            handleCancelledStartup()
            throw error
        }
        
        if Task.isCancelled || sessionID != id {
            handleCancelledStartup()
            return
        }
        
        audioLevel = 0.0
        
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                self?.receiveRecognition(
                    session: id,
                    text: result?.bestTranscription.formattedString,
                    isFinal: result?.isFinal == true,
                    failed: error != nil,
                    onResult: onResult
                )
            }
        }
        
        isRecording = true
    }

    private func availableSpeechRecognizer() async -> SFSpeechRecognizer? {
        for attempt in 0..<5 {
            if Task.isCancelled { return nil }
            if let recognizer = SFSpeechRecognizer(), recognizer.isAvailable {
                return recognizer
            }
            if attempt < 4 {
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        return nil
    }
    
    func stopDictation() {
        sessionID = nil
        resolveFinalization(false)
        // Startup owns its engine until the detached configuration joins.
        if !isConfiguringEngine { teardownAudioEngine() }
        audioLevel = 0.0
        isRecording = false
    }

    /// End input and await the terminal transcript before freezing a submission.
    /// Ordinary stop remains cancellation; callers must retain editable text on false.
    func finishDictation(timeout: Duration = .seconds(3)) async -> Bool {
        guard !isStarting else {
            stopDictation()
            return false
        }
        guard isRecording, let id = sessionID else { return !Task.isCancelled }
        guard finalization == nil else { return false }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled, sessionID == id else {
                    continuation.resume(returning: false)
                    return
                }
                finalization = continuation
                finalizationTimeout = Task { [weak self] in
                    do { try await Task.sleep(for: timeout) } catch { return }
                    guard self?.sessionID == id else { return }
                    self?.stopDictation()
                }
                stopAudioInput()
                recognitionRequest?.endAudio()
                recognitionTask?.finish()
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard self?.sessionID == id else { return }
                self?.stopDictation()
            }
        }
    }

    private func requireCurrentSession(_ id: UUID) throws {
        guard !Task.isCancelled, sessionID == id else { throw CancellationError() }
    }

    private func receiveRecognition(
        session id: UUID, text: String?, isFinal: Bool, failed: Bool,
        onResult: @MainActor (String) -> Void
    ) {
        guard sessionID == id else { return }
        if let text { onResult(text) }
        guard sessionID == id, isFinal || failed else { return }
        sessionID = nil
        teardownAudioEngine()
        audioLevel = 0
        isRecording = false
        resolveFinalization(isFinal && !failed)
    }

    private func resolveFinalization(_ succeeded: Bool) {
        let completion = finalization
        finalization = nil
        finalizationTimeout?.cancel()
        finalizationTimeout = nil
        completion?.resume(returning: succeeded)
    }

    private func stopAudioInput() {
        guard let audioEngine else { return }
        audioEngine.stop()
        if hasInputTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInputTap = false
        }
    }
    private func teardownAudioEngine() {
        stopAudioInput()
        audioEngine = nil

        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        recognitionRequest = nil
        recognitionTask = nil
        let lease = audioSessionLease
        audioSessionLease = nil
        let priorRelease = releaseTask
        releaseTask = Task {
            await priorRelease?.value
            await AudioSessionCoordinator.shared.deactivate(ifCurrent: lease)
        }
    }

    private func handleCancelledStartup() {
        stopDictation()
    }

#if DEBUG
    func debugHandleStartupCancellation() {
        handleCancelledStartup()
    }

    var debugHasAudioEngine: Bool { audioEngine != nil }

    func debugBeginRecognition() -> UUID {
        stopDictation()
        let id = UUID()
        sessionID = id
        isRecording = true
        return id
    }

    func debugReceiveRecognition(
        session: UUID, text: String?, isFinal: Bool = false, failed: Bool = false,
        onResult: @MainActor (String) -> Void
    ) {
        receiveRecognition(session: session, text: text, isFinal: isFinal,
                           failed: failed, onResult: onResult)
    }

    var debugIsFinalizing: Bool { finalization != nil }
#endif
}
