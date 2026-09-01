import Foundation
import Testing

@testable import Merian

@MainActor
@Suite("Insight media export lifecycle")
struct InsightMediaExportLifecycleTests {
    @Test("Dismissal fences an uncooperative save completion")
    func dismissalFencesSaveCompletion() async {
        let gate = AsyncValueGate<MediaSaveResult>()
        var successFeedbackCount = 0
        var errorFeedbackCount = 0
        let dependencies = InsightShellDependencies(
            successFeedback: { successFeedbackCount += 1 },
            errorFeedback: { errorFeedbackCount += 1 },
            saveMedia: { _ in await gate.wait() }
        )
        let (viewModel, engine, scanID) = makePresentedViewModel(
            dependencies: dependencies
        )
        viewModel.beginPresentationSession()
        let generation = viewModel.scanBoundActionGeneration

        viewModel.saveUserMedia(
            expectedScanId: scanID,
            expectedGeneration: generation,
            inferenceEngine: engine
        )
        await gate.waitUntilStarted()
        viewModel.endPresentationSession()

        var result = MediaSaveResult()
        result.record(.photo, success: true)
        await gate.resume(returning: result)
        await Task.yield()

        #expect(successFeedbackCount == 0)
        #expect(errorFeedbackCount == 0)
        #expect(!viewModel.state.showMediaSaveAlert)
        #expect(!viewModel.state.isSavingMedia)
        #expect(viewModel.mediaSaveTask == nil)
    }

    @Test("Dismissal fences an uncooperative share completion")
    func dismissalFencesShareCompletion() async {
        let gate = AsyncValueGate<MediaSharePayload>()
        var presentationCount = 0
        let dependencies = InsightShellDependencies(
            prepareMediaShare: { _ in await gate.wait() },
            presentMediaShare: { _ in presentationCount += 1 }
        )
        let (viewModel, engine, scanID) = makePresentedViewModel(
            dependencies: dependencies
        )
        viewModel.beginPresentationSession()
        let generation = viewModel.scanBoundActionGeneration

        viewModel.shareDiscovery(
            expectedScanId: scanID,
            expectedGeneration: generation,
            inferenceEngine: engine
        )
        await gate.waitUntilStarted()
        viewModel.endPresentationSession()
        await gate.resume(
            returning: MediaSharePayload(items: [.text("stale")])
        )
        await Task.yield()

        #expect(presentationCount == 0)
        #expect(viewModel.mediaShareTask == nil)
    }

    @Test("Presentation session invalidation is idempotent")
    func presentationSessionInvalidationIsIdempotent() {
        let viewModel = InsightSheetViewModel()
        viewModel.beginPresentationSession()
        let initialGeneration = viewModel.scanBoundActionGeneration

        viewModel.endPresentationSession()
        let closedGeneration = viewModel.scanBoundActionGeneration
        viewModel.endPresentationSession()

        #expect(closedGeneration == initialGeneration + 1)
        #expect(viewModel.scanBoundActionGeneration == closedGeneration)
        #expect(!viewModel.presentationSessionIsActive)
    }

    private func makePresentedViewModel(
        dependencies: InsightShellDependencies
    ) -> (InsightSheetViewModel, InferenceEngine, String) {
        let scanID = "media-export-session"
        let engine = InsightSheetTestSupport.biologicalEngine(scanId: scanID)
        engine.activeMedia = ActiveScanMedia(items: [.image("capture.webp")])
        let viewModel = InsightSheetViewModel(
            inferenceEngine: engine,
            dependencies: dependencies
        )
        InsightSheetTestSupport.bindToolbarPresentation(
            viewModel,
            scanId: scanID
        )
        return (viewModel, engine, scanID)
    }
}

private actor AsyncValueGate<Value: Sendable> {
    private var continuation: CheckedContinuation<Value, Never>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var didStart = false

    func wait() async -> Value {
        didStart = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilStarted() async {
        guard !didStart else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func resume(returning value: Value) {
        continuation?.resume(returning: value)
        continuation = nil
    }
}
