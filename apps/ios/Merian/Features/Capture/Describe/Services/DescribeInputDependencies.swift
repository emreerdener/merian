import Foundation

extension DescribeInputViewModel.Dependencies {
    @MainActor
    static func live(speechManager: SpeechManager) -> Self {
        Self(
            startDictation: { resultSink in
                guard !speechManager.isStarting,
                      !speechManager.isRecording else {
                    return false
                }
                try await speechManager.startDictation { transcription in
                    resultSink.yield(transcription)
                }
                return speechManager.isRecording
            },
            stopDictation: {
                speechManager.stopDictation()
            },
            waitForSubjectInference: {
                try await Task.sleep(for: .seconds(1.5))
            },
            inferSubjectId: { text in
                SubjectKeywordMatcher.infer(from: text)
            }
        )
    }
}
