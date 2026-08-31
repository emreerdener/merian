struct FieldNotesDictationResultSink {
    let yield: @MainActor (_ transcription: String) -> Void
}

struct FieldNotesEditorDependencies {
    let dictationFeedback: @MainActor () -> Void
    let startDictation:
        @MainActor (
            _ resultSink: FieldNotesDictationResultSink
        ) async throws -> Bool
    let stopDictation: @MainActor () -> Void

    init(
        dictationFeedback: @escaping @MainActor () -> Void = {},
        startDictation:
            @escaping @MainActor (
                _ resultSink: FieldNotesDictationResultSink
            ) async throws -> Bool = { _ in false },
        stopDictation: @escaping @MainActor () -> Void = {}
    ) {
        self.dictationFeedback = dictationFeedback
        self.startDictation = startDictation
        self.stopDictation = stopDictation
    }

    @MainActor
    static func live(speechManager: SpeechManager) -> Self {
        let hapticManager = AppDIContainer.shared.hapticManager
        return Self(
            dictationFeedback: {
                hapticManager.triggerMediumPulse()
            },
            startDictation: { resultSink in
                guard !speechManager.isStarting,
                    !speechManager.isRecording
                else {
                    return false
                }
                try await speechManager.startDictation { transcription in
                    resultSink.yield(transcription)
                }
                return speechManager.isRecording
            },
            stopDictation: {
                speechManager.stopDictation()
            }
        )
    }
}
