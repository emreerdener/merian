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
    var audioLevel: CGFloat = 0.0
    
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    func startDictation(onResult: @MainActor @escaping (String) -> Void) async throws {
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
        
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true)
        
        if Task.isCancelled {
            try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            return
        }
        
        audioLevel = 0.0
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }
        
        recognitionRequest.shouldReportPartialResults = true
        
        recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
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
        
        let inputNode = audioEngine.inputNode

        // Pass nil so AVAudioEngine negotiates the native hardware format itself.
        // Querying outputFormat(forBus: 0) before the audio session has fully settled
        // can return a 0 Hz format, which causes installTap to throw IsFormatSampleRateAndChannelCountValid.
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            recognitionRequest.append(buffer)
            
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
            
            Task { @MainActor [weak self] in
                self?.audioLevel = level
            }
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        
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
        recognitionTask?.cancel()

        recognitionRequest = nil
        recognitionTask = nil

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
