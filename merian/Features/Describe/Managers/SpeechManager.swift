import AVFoundation
import Foundation
import Speech

struct PermissionError: LocalizedError {
    var errorDescription: String? {
        return "Microphone access required. Check Settings."
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

    func startDictation(onResult: @MainActor @escaping (String) -> Void) async throws {
        guard !isStarting, !isRecording else { return }
        isStarting = true
        defer { isStarting = false }

        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            return
        }
        
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard speechStatus == .authorized else {
            throw PermissionError()
        }
        
        if Task.isCancelled { return }
        
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
        
        try await Task.detached { [manager] in
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            
            #if targetEnvironment(simulator)
            // Simulator specific fix: iOS forces 0 Hz sample rates randomly causing -10851 aborts.
            try? audioSession.setPreferredSampleRate(48000)
            #endif
            
            try audioSession.setActive(true)
            
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
        
        if Task.isCancelled {
            Task.detached {
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
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
    
    func stopDictation() {
        teardownAudioEngine()
        isRecording = false
    }
    
    private func teardownAudioEngine() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        recognitionRequest?.endAudio()
        recognitionTask?.finish()

        recognitionRequest = nil
        recognitionTask = nil

        // Prevent mediaserverd IPC wait from deadlocking MainActor tearing down the session
        Task.detached {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}
