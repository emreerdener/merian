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
    
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioSessionLease: AudioSessionCoordinator.Lease?

    #if targetEnvironment(simulator)
    private static let preferredRecordSampleRate: Double? = 48_000
    #else
    private static let preferredRecordSampleRate: Double? = nil
    #endif

    func startDictation(onResult: @MainActor @escaping (String) -> Void) async throws {
        guard !isStarting, !isRecording else { return }
        isStarting = true
        defer { isStarting = false }

        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard speechStatus == .authorized else {
            throw PermissionError()
        }
        
        if Task.isCancelled { return }

        guard let recognizer = await availableSpeechRecognizer() else {
            throw DictationUnavailableError()
        }
        
        let micStatus = await AVAudioApplication.requestRecordPermission()
        guard micStatus else {
            throw PermissionError()
        }
        
        if Task.isCancelled { return }
        
        teardownAudioEngine()
        
        // on the iOS Simulator's HALC_ShellPlugIn.
        let engine = audioEngine
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request
        let manager = self
        
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
                        manager.audioLevel = level
                    }
                }
                
                engine.prepare()
                try engine.start()
            }.value
        } catch {
            handleCancelledStartup()
            throw error
        }
        
        if Task.isCancelled {
            handleCancelledStartup()
            return
        }
        
        audioLevel = 0.0
        
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                
                if let result = result {
                    onResult(result.bestTranscription.formattedString)
                }
                
                if error != nil || result?.isFinal == true {
                    self.stopDictation()
                }
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
        teardownAudioEngine()
        audioLevel = 0.0
        isRecording = false
    }
    
    private func teardownAudioEngine() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        recognitionRequest?.endAudio()
        recognitionTask?.finish()

        recognitionRequest = nil
        recognitionTask = nil
        let lease = audioSessionLease
        audioSessionLease = nil
        Task {
            await AudioSessionCoordinator.shared.deactivate(ifCurrent: lease)
        }
    }

    private func handleCancelledStartup() {
        teardownAudioEngine()
        audioLevel = 0.0
        isRecording = false
    }

#if DEBUG
    func debugHandleStartupCancellation() {
        handleCancelledStartup()
    }
#endif
}
