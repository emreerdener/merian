import Foundation
import Testing

@testable import Merian

@Suite("Field Notes Editor View Model")
@MainActor
struct FieldNotesEditorViewModelTests {
    @Test("An unchanged draft dismisses without writes")
    func unchangedDraftIsNoOp() async {
        var committedTexts: [String] = []
        let saveRecorder = VisibilitySaveRecorder()
        let viewModel = makeViewModel(
            initialText: "Creek observation",
            initialIsPublic: true
        )
        let configuration = visibilityConfiguration(
            initialIsPublic: true,
            saveRecorder: saveRecorder
        )

        let shouldDismiss = await viewModel.saveDraft(
            visibilityConfiguration: configuration,
            onCommit: { committedTexts.append($0) }
        )

        #expect(shouldDismiss)
        #expect(viewModel.didFinalizeBeforeDismiss)
        #expect(committedTexts.isEmpty)
        #expect(saveRecorder.requests.isEmpty)
    }

    @Test("A private edit commits without a visibility write")
    func privateEditCommitsLocally() async {
        var committedTexts: [String] = []
        let viewModel = makeViewModel(initialText: "Original")
        viewModel.updateDraftText("Updated")

        let shouldDismiss = await viewModel.saveDraft(
            visibilityConfiguration: nil,
            onCommit: { committedTexts.append($0) }
        )

        #expect(shouldDismiss)
        #expect(viewModel.didFinalizeBeforeDismiss)
        #expect(committedTexts == ["Updated"])
    }

    @Test("A successful public edit sends one normalized request")
    func successfulVisibilitySave() async {
        var committedTexts: [String] = []
        let saveRecorder = VisibilitySaveRecorder()
        let viewModel = makeViewModel(initialText: "Original")
        viewModel.updateDraftText("Updated")
        viewModel.updateDraftVisibility(true)
        let configuration = visibilityConfiguration(
            initialIsPublic: false,
            feedback: .success(isPublic: true),
            saveRecorder: saveRecorder
        )

        let shouldDismiss = await viewModel.saveDraft(
            visibilityConfiguration: configuration,
            onCommit: { committedTexts.append($0) }
        )

        #expect(shouldDismiss)
        #expect(viewModel.didFinalizeBeforeDismiss)
        #expect(viewModel.draftIsPublic)
        #expect(committedTexts == ["Updated"])
        #expect(
            saveRecorder.requests == [
                FieldNotesVisibilityUpdateRequest(
                    text: "Updated",
                    isPublic: true
                )
            ]
        )
    }

    @Test("A failed visibility edit keeps the editor open with feedback")
    func failedVisibilitySave() async {
        var committedTexts: [String] = []
        let saveRecorder = VisibilitySaveRecorder()
        let viewModel = makeViewModel(initialText: "Original")
        viewModel.updateDraftText("Updated")
        let configuration = visibilityConfiguration(
            initialIsPublic: false,
            feedback: .failure("Unable to update field notes."),
            saveRecorder: saveRecorder
        )

        let shouldDismiss = await viewModel.saveDraft(
            visibilityConfiguration: configuration,
            onCommit: { committedTexts.append($0) }
        )

        #expect(!shouldDismiss)
        #expect(!viewModel.didFinalizeBeforeDismiss)
        #expect(viewModel.saveErrorMessage == "Unable to update field notes.")
        #expect(committedTexts == ["Updated"])
        #expect(saveRecorder.requests.count == 1)
    }

    @Test("Disappearing commits a changed draft and returns its save request")
    func disappearancePreparesChangedDraft() {
        var committedTexts: [String] = []
        let viewModel = makeViewModel(
            initialText: "Original",
            initialIsPublic: true
        )
        viewModel.updateDraftText("   ")

        let request = viewModel.prepareForDisappear {
            committedTexts.append($0)
        }
        let repeatedRequest = viewModel.prepareForDisappear { _ in
            Issue.record("A finalized disappearance must not commit twice")
        }

        #expect(request == .init(text: "   ", isPublic: false))
        #expect(repeatedRequest == nil)
        #expect(viewModel.didFinalizeBeforeDismiss)
        #expect(committedTexts == ["   "])
    }

    @Test("Disappearing during an active save does not duplicate the write")
    func disappearanceDoesNotDuplicateActiveSave() async {
        let saveWaiter = VisibilitySaveWaiter()
        var committedTexts: [String] = []
        let viewModel = makeViewModel(initialText: "Original")
        viewModel.updateDraftText("Updated")
        let configuration = FieldNotesVisibilityConfiguration(
            initialIsPublic: false,
            onSave: { text, isPublic in
                await saveWaiter.save(
                    .init(text: text, isPublic: isPublic)
                )
                return .success(isPublic: isPublic)
            }
        )

        let saveTask = Task {
            await viewModel.saveDraft(
                visibilityConfiguration: configuration,
                onCommit: { committedTexts.append($0) }
            )
        }
        await waitUntil {
            viewModel.isSaving && saveWaiter.requests.count == 1
        }

        let duplicateRequest = viewModel.prepareForDisappear {
            committedTexts.append($0)
        }

        #expect(duplicateRequest == nil)
        #expect(committedTexts == ["Updated"])
        #expect(saveWaiter.requests == [.init(text: "Updated", isPublic: false)])

        saveWaiter.resume()
        let didSave = await saveTask.value
        #expect(didSave)
    }

    @Test("Clearing notes also clears effective visibility")
    func clearingNotesClearsVisibility() {
        let viewModel = makeViewModel(
            initialText: "Published note",
            initialIsPublic: true
        )

        viewModel.clearDraft()

        #expect(viewModel.draftText.isEmpty)
        #expect(!viewModel.draftIsPublic)
        #expect(!viewModel.hasNotes)
        #expect(viewModel.changes == [.content, .visibility])
    }

    @Test("Partial dictation replaces only its current transcription")
    func dictationUsesStableBaseText() async {
        var resultSinks: [FieldNotesDictationResultSink] = []
        let viewModel = makeViewModel(
            initialText: "Near the creek",
            startDictation: {
                resultSinks.append($0)
                return true
            }
        )

        viewModel.toggleDictation(isSpeechRecording: false)
        await waitUntil { resultSinks.count == 1 }
        resultSinks[0].yield("one bird")
        resultSinks[0].yield("two birds")

        #expect(viewModel.draftText == "Near the creek two birds")
        #expect(viewModel.isDictationSessionActive)
    }

    @Test("A stale transcription cannot mutate a replacement session")
    func staleTranscriptionIsSessionFenced() async {
        var resultSinks: [FieldNotesDictationResultSink] = []
        var stopCount = 0
        let viewModel = makeViewModel(
            initialText: "First",
            startDictation: {
                resultSinks.append($0)
                return true
            },
            stopDictation: { stopCount += 1 }
        )

        viewModel.toggleDictation(isSpeechRecording: false)
        await waitUntil { resultSinks.count == 1 }
        viewModel.stopDictation()
        viewModel.updateDraftText("Second")
        viewModel.toggleDictation(isSpeechRecording: false)
        await waitUntil { resultSinks.count == 2 }

        resultSinks[0].yield("stale result")
        resultSinks[1].yield("new result")

        #expect(viewModel.draftText == "Second new result")
        #expect(stopCount == 1)
        #expect(viewModel.isDictationSessionActive)
    }

    @Test("Automatic speech termination fences late transcription")
    func automaticSpeechTerminationFencesLateTranscription() async {
        var resultSinks: [FieldNotesDictationResultSink] = []
        var stopCount = 0
        let viewModel = makeViewModel(
            initialText: "Before termination",
            startDictation: {
                resultSinks.append($0)
                return true
            },
            stopDictation: { stopCount += 1 }
        )

        viewModel.toggleDictation(isSpeechRecording: false)
        await waitUntil { resultSinks.count == 1 }

        viewModel.speechRecordingDidChange(isRecording: false)
        resultSinks[0].yield("late result")

        #expect(!viewModel.isDictationSessionActive)
        #expect(viewModel.draftText == "Before termination")
        #expect(stopCount == 0)
    }

    @Test("Replacement dictation waits for canceled startup teardown")
    func replacementWaitsForCanceledStartup() async {
        let startupWaiter = DictationStartupWaiter()
        var stopCount = 0
        let viewModel = makeViewModel(
            startDictation: { resultSink in
                await startupWaiter.start(resultSink)
                return true
            },
            stopDictation: { stopCount += 1 }
        )

        viewModel.toggleDictation(isSpeechRecording: false)
        await waitUntil { startupWaiter.waitCount == 1 }
        viewModel.stopDictation()
        viewModel.toggleDictation(isSpeechRecording: false)

        for _ in 0..<10 {
            await Task.yield()
        }
        #expect(startupWaiter.waitCount == 1)
        #expect(stopCount == 0)

        startupWaiter.resumeStart(at: 0)
        await waitUntil { startupWaiter.waitCount == 2 }
        #expect(stopCount == 1)

        startupWaiter.resultSinks[0].yield("stale result")
        startupWaiter.resultSinks[1].yield("new result")
        startupWaiter.resumeStart(at: 1)

        #expect(viewModel.draftText == "new result")
        #expect(viewModel.isDictationSessionActive)
    }

    @Test("Startup failures end the session and expose their message")
    func startupFailureEndsSession() async {
        let viewModel = makeViewModel(
            startDictation: { _ in throw FieldNotesTestFailure.expected }
        )

        viewModel.toggleDictation(isSpeechRecording: false)
        await waitUntil { viewModel.dictationErrorMessage != nil }

        #expect(!viewModel.isDictationSessionActive)
        #expect(viewModel.dictationErrorMessage == "Expected failure")
    }

    @Test("A busy speech owner ends the unstarted session")
    func busySpeechOwnerEndsSession() async {
        let viewModel = makeViewModel(startDictation: { _ in false })

        viewModel.toggleDictation(isSpeechRecording: false)
        await waitUntil { !viewModel.isDictationSessionActive }

        #expect(viewModel.dictationErrorMessage == nil)
    }

    @Test("Stopping only tears down a session owned by this editor")
    func stopOnlyAffectsOwnedSession() async {
        var startCount = 0
        var stopCount = 0
        let viewModel = makeViewModel(
            startDictation: { _ in
                startCount += 1
                return true
            },
            stopDictation: { stopCount += 1 }
        )

        viewModel.stopDictation()
        #expect(stopCount == 0)

        viewModel.toggleDictation(isSpeechRecording: false)
        await waitUntil { startCount == 1 }
        viewModel.stopDictation()
        viewModel.stopDictation()
        await waitUntil { stopCount == 1 }

        #expect(stopCount == 1)
        #expect(!viewModel.isDictationSessionActive)
    }

    private func makeViewModel(
        initialText: String = "",
        initialIsPublic: Bool = false,
        startDictation:
            @escaping @MainActor (
                FieldNotesDictationResultSink
            ) async throws -> Bool = { _ in true },
        stopDictation: @escaping @MainActor () -> Void = {}
    ) -> FieldNotesEditorViewModel {
        FieldNotesEditorViewModel(
            initialText: initialText,
            initialIsPublic: initialIsPublic,
            dependencies: .init(
                startDictation: startDictation,
                stopDictation: stopDictation
            )
        )
    }

    private func visibilityConfiguration(
        initialIsPublic: Bool,
        feedback: FieldNotesVisibilityUpdateFeedback = .success(
            isPublic: true
        ),
        saveRecorder: VisibilitySaveRecorder
    ) -> FieldNotesVisibilityConfiguration {
        FieldNotesVisibilityConfiguration(
            initialIsPublic: initialIsPublic,
            onSave: { text, isPublic in
                saveRecorder.requests.append(
                    .init(text: text, isPublic: isPublic)
                )
                return feedback
            }
        )
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<100 where !condition() {
            await Task.yield()
        }
        #expect(condition())
    }
}

@MainActor
private final class VisibilitySaveRecorder {
    var requests: [FieldNotesVisibilityUpdateRequest] = []
}

@MainActor
private final class VisibilitySaveWaiter {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var requests: [FieldNotesVisibilityUpdateRequest] = []

    func save(_ request: FieldNotesVisibilityUpdateRequest) async {
        requests.append(request)
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class DictationStartupWaiter {
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private(set) var resultSinks: [FieldNotesDictationResultSink] = []

    var waitCount: Int { continuations.count }

    func start(_ resultSink: FieldNotesDictationResultSink) async {
        resultSinks.append(resultSink)
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func resumeStart(at index: Int) {
        continuations[index].resume()
    }
}

private enum FieldNotesTestFailure: LocalizedError {
    case expected

    var errorDescription: String? { "Expected failure" }
}
