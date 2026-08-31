import Foundation
import Observation

@MainActor
@Observable
final class FieldNotesEditorViewModel {
    private(set) var draftText: String
    private(set) var draftIsPublic: Bool
    private(set) var isSaving = false
    private(set) var dictationErrorMessage: String?
    private(set) var saveErrorMessage: String?
    private(set) var didFinalizeBeforeDismiss = false
    private(set) var isDictationSessionActive = false

    private let initialText: String
    private let initialIsPublic: Bool
    @ObservationIgnored private let dependencies: FieldNotesEditorDependencies
    @ObservationIgnored private var dictationStartupTask: Task<Void, Never>?
    @ObservationIgnored private var priorDictationStartupTask: Task<Void, Never>?
    @ObservationIgnored private var priorDictationStartupGeneration: Int?
    @ObservationIgnored private var dictationStartupGeneration: Int?
    @ObservationIgnored private var activeDictationGeneration: Int?
    @ObservationIgnored private var dictationGeneration = 0

    init(
        initialText: String,
        initialIsPublic: Bool,
        dependencies: FieldNotesEditorDependencies
    ) {
        self.initialText = initialText
        self.initialIsPublic = initialIsPublic
        self.draftText = initialText
        self.draftIsPublic = initialIsPublic
        self.dependencies = dependencies
    }

    var hasNotes: Bool {
        FieldNotesEditPolicy.normalizedText(draftText) != nil
    }

    var changes: FieldNotesEditChanges {
        FieldNotesEditPolicy.changes(
            initialText: initialText,
            initialIsPublic: initialIsPublic,
            draftText: draftText,
            draftIsPublic: draftIsPublic
        )
    }

    var visibilityDetailText: String {
        if !hasNotes {
            return "Add field notes before showing them on Explore."
        }

        return draftIsPublic
            ? "Field notes appear on this post."
            : "Keep these field notes off this post."
    }

    func isDictating(isSpeechRecording: Bool) -> Bool {
        isDictationSessionActive && isSpeechRecording
    }

    func updateDraftText(_ text: String) {
        draftText = text
        if !hasNotes {
            draftIsPublic = false
        }
    }

    func updateDraftVisibility(_ isPublic: Bool) {
        draftIsPublic = isPublic && hasNotes
    }

    func toggleDictation(isSpeechRecording: Bool) {
        dependencies.dictationFeedback()
        if isDictating(isSpeechRecording: isSpeechRecording) {
            stopDictation()
        } else {
            startDictation()
        }
    }

    func speechRecordingDidChange(isRecording: Bool) {
        guard !isRecording, isDictationSessionActive else { return }
        invalidateDictationSession()
    }

    func clearDraft() {
        stopDictation()
        draftText = ""
        draftIsPublic = false
    }

    func saveDraft(
        visibilityConfiguration: FieldNotesVisibilityConfiguration?,
        onCommit: @MainActor (_ text: String) -> Void
    ) async -> Bool {
        guard !isSaving else { return false }

        stopDictation()
        saveErrorMessage = nil

        guard !changes.isEmpty else {
            didFinalizeBeforeDismiss = true
            return true
        }

        let request = visibilityUpdateRequest
        onCommit(request.text)

        guard let visibilityConfiguration else {
            didFinalizeBeforeDismiss = true
            return true
        }

        isSaving = true
        let feedback = await visibilityConfiguration.onSave(
            request.text,
            request.isPublic
        )
        isSaving = false

        switch feedback {
        case .success(let isPublic):
            draftIsPublic = isPublic
            didFinalizeBeforeDismiss = true
            return true
        case .failure(let message):
            saveErrorMessage = message
            return false
        }
    }

    func prepareForDisappear(
        onCommit: @MainActor (_ text: String) -> Void
    ) -> FieldNotesVisibilityUpdateRequest? {
        stopDictation()

        guard !didFinalizeBeforeDismiss,
            !isSaving,
            !changes.isEmpty
        else {
            return nil
        }

        let request = visibilityUpdateRequest
        onCommit(request.text)
        didFinalizeBeforeDismiss = true
        return request
    }

    func stopDictation() {
        let ownsSession =
            isDictationSessionActive
            || dictationStartupTask != nil
        guard ownsSession else { return }

        let hadPendingStartup = invalidateDictationSession()
        if !hadPendingStartup {
            dependencies.stopDictation()
        }
    }

    private var visibilityUpdateRequest: FieldNotesVisibilityUpdateRequest {
        FieldNotesVisibilityUpdateRequest(
            text: draftText,
            isPublic: hasNotes && draftIsPublic
        )
    }

    private func startDictation() {
        guard !isDictationSessionActive else { return }

        dictationErrorMessage = nil
        let baseText = draftText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let priorStartupTask = priorDictationStartupTask
        priorDictationStartupTask = nil
        priorDictationStartupGeneration = nil
        dictationGeneration &+= 1
        let generation = dictationGeneration
        activeDictationGeneration = generation
        dictationStartupGeneration = generation
        isDictationSessionActive = true
        let dependencies = dependencies

        dictationStartupTask = Task { [weak self] in
            defer {
                self?.finishDictationStartup(generation: generation)
            }

            if let priorStartupTask {
                await priorStartupTask.value
            }
            guard !Task.isCancelled,
                let self,
                self.activeDictationGeneration == generation,
                self.isDictationSessionActive
            else {
                return
            }

            do {
                let didStart = try await dependencies.startDictation(
                    FieldNotesDictationResultSink { [weak self] transcription in
                        guard let self,
                            self.activeDictationGeneration == generation,
                            self.isDictationSessionActive,
                            let composedText = Self.dictationText(
                                baseText: baseText,
                                transcription: transcription
                            )
                        else {
                            return
                        }
                        self.updateDraftText(composedText)
                    }
                )

                guard !Task.isCancelled,
                    self.activeDictationGeneration == generation,
                    self.isDictationSessionActive
                else {
                    if didStart {
                        dependencies.stopDictation()
                    }
                    return
                }

                if !didStart {
                    self.finishDictationSession(generation: generation)
                }
            } catch {
                guard !Task.isCancelled,
                    self.finishDictationSession(generation: generation)
                else {
                    return
                }
                self.dictationErrorMessage = error.localizedDescription
            }
        }
    }

    @discardableResult
    private func invalidateDictationSession() -> Bool {
        dictationGeneration &+= 1
        activeDictationGeneration = nil
        isDictationSessionActive = false
        let hadPendingStartup = dictationStartupTask != nil
        if let dictationStartupTask {
            dictationStartupTask.cancel()
            priorDictationStartupTask = dictationStartupTask
            priorDictationStartupGeneration = dictationStartupGeneration
        }
        dictationStartupTask = nil
        dictationStartupGeneration = nil
        return hadPendingStartup
    }

    private func finishDictationStartup(generation: Int) {
        if dictationStartupGeneration == generation {
            dictationStartupTask = nil
            dictationStartupGeneration = nil
        }
        if priorDictationStartupGeneration == generation {
            priorDictationStartupTask = nil
            priorDictationStartupGeneration = nil
        }
    }

    @discardableResult
    private func finishDictationSession(generation: Int) -> Bool {
        guard activeDictationGeneration == generation else { return false }
        activeDictationGeneration = nil
        isDictationSessionActive = false
        if dictationStartupGeneration == generation {
            dictationStartupTask = nil
            dictationStartupGeneration = nil
        }
        return true
    }

    private static func dictationText(
        baseText: String,
        transcription: String
    ) -> String? {
        let trimmedTranscription = transcription.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmedTranscription.isEmpty else { return nil }
        return baseText.isEmpty
            ? trimmedTranscription
            : baseText + " " + trimmedTranscription
    }
}
