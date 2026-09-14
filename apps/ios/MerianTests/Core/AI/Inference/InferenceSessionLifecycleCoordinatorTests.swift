import Foundation
import Testing

@testable import Merian

private actor InferenceSessionLifecycleGate {
    private var started = false
    private var released = false
    private var startContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func wait() async {
        started = true
        startContinuation?.resume()
        startContinuation = nil
        guard !released else { return }
        await withCheckedContinuation { releaseContinuation = $0 }
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { startContinuation = $0 }
    }

    func release() {
        released = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

@MainActor
@Suite("Inference Session Lifecycle Coordinator")
struct InferenceLifecycleCoordinatorTests {
    @Test func newScanPreparationResetsEveryDisplacedOwner() async throws {
        let harness = InferenceSessionLifecycleHarness()
        let oldAttempt = UUID()
        let oldForeground = UUID()
        let newAttempt = UUID()
        let task = Task<Void, Error> {
            try await Task.sleep(for: .seconds(60))
        }
        harness.attempt.replaceTask(task)
        harness.attempt.activate(
            scanId: "old-scan",
            attemptGeneration: oldAttempt,
            foregroundGeneration: oldForeground
        )
        harness.attempt.setRecoverablePresentationScanId("old-scan")
        harness.hydration.recordEnrichmentRateLimit(for: 60)
        harness.state.setQueuedPresentationScanId("old-scan")
        harness.state.setEnrichmentLoading(true)
        harness.state.setLookalikesLoading(true)
        harness.state.replaceSpeciesData(
            inferenceSessionLifecycleSpeciesData(scanId: "old-scan")
        )
        harness.state.replaceActiveMedia(
            ActiveScanMedia(items: [.image("old.webp")])
        )
        let priorWriteGeneration = harness.writes.generation

        harness.coordinator.prepareForNewScan(
            scanId: "new-scan",
            attemptGeneration: newAttempt,
            modality: .visual
        )

        #expect(task.isCancelled)
        #expect(harness.attempt.activeScanId == nil)
        #expect(harness.attempt.activeAttemptGeneration == nil)
        #expect(harness.attempt.activeForegroundGeneration == nil)
        #expect(harness.attempt.recoverablePresentationScanId == nil)
        #expect(harness.hydration.canAttemptEnrichment())
        #expect(harness.writes.generation == priorWriteGeneration + 1)
        #expect(harness.state.isProcessing)
        #expect(harness.state.queuedPresentationScanId == nil)
        #expect(harness.state.speciesData == nil)
        #expect(harness.state.activeMedia.isEmpty)
        #expect(!harness.state.isEnrichmentLoading)
        #expect(!harness.state.isLookalikesLoading)
        #expect(harness.queue.events == [
            .release("old-scan", oldForeground, "live_scan_replaced"),
            .retire("old-scan", oldForeground, true, "live_scan_replaced")
        ])

        let handoff = try #require(harness.presentation.transitionToQueue(
            scanId: "new-scan",
            source: .prepared(attemptGeneration: newAttempt),
            isActiveAttemptCurrent: { _, _ in false },
            activeMediaItemCount: 0,
            activeVisualPhrases: [],
            preparedVisualPhrases: ["Prepared"]
        ))
        #expect(handoff.scanningPhrases == ["Prepared"])
        _ = await task.result
    }

    @Test func visualAnalysisReplacementClearsTransientOwnersAndLoaders() {
        let harness = InferenceSessionLifecycleHarness()
        let attempt = UUID()
        let foreground = UUID()
        let media = ActiveScanMedia(items: [.image("capture.webp")])
        let result = inferenceSessionLifecycleSpeciesData(scanId: "scan-a")
        harness.attempt.activate(
            scanId: "scan-a",
            attemptGeneration: attempt,
            foregroundGeneration: foreground
        )
        harness.state.replaceActiveMedia(media)
        harness.state.replaceSpeciesData(result)
        harness.state.setEnrichmentLoading(true)
        harness.state.setLookalikesLoading(true)
        harness.presentation.activate(
            scanId: "scan-a",
            attemptGeneration: attempt,
            modality: .visual
        )
        #expect(harness.presentation.transitionToQueue(
            scanId: "scan-a",
            source: .active(attemptGeneration: attempt),
            isActiveAttemptCurrent: { _, _ in true },
            activeMediaItemCount: 1,
            activeVisualPhrases: ["Scanning wings"],
            preparedVisualPhrases: []
        ) != nil)
        #expect(harness.presentation.hasVisualQueueHandoff(for: "scan-a"))
        #expect(harness.presentation.hasLiveMedia(for: "scan-a"))
        harness.presentation.activate(
            scanId: "scan-a",
            attemptGeneration: attempt,
            modality: .visual
        )
        harness.presentation.beginFirstRenderMetric(
            scanId: "scan-a",
            startedAt: 42
        )

        harness.coordinator.prepareForVisualAnalysis()

        #expect(harness.attempt.activeScanId == nil)
        #expect(!harness.presentation.isActiveVisual(
            attemptGeneration: attempt
        ))
        #expect(!harness.presentation.hasVisualQueueHandoff(for: "scan-a"))
        #expect(!harness.presentation.hasLiveMedia(for: "scan-a"))
        #expect(
            harness.presentation.scanningPhrases(for: "scan-a").isEmpty
        )
        #expect(
            harness.presentation.consumeFirstRenderStart(
                scanId: "scan-a"
            ) == nil
        )
        #expect(harness.state.activeMedia == media)
        #expect(harness.state.speciesData?.scanId == result.scanId)
        #expect(!harness.state.isEnrichmentLoading)
        #expect(!harness.state.isLookalikesLoading)
        #expect(harness.queue.events == [
            .release(
                "scan-a",
                foreground,
                "live_scan_replaced_by_analyze"
            ),
            .retire(
                "scan-a",
                foreground,
                true,
                "live_scan_replaced_by_analyze"
            )
        ])
    }

    @Test func visualReplacementCancelsOnlyTheDisplacedTask() async {
        let harness = InferenceSessionLifecycleHarness()
        let displacedTask = Task<Void, Error> {
            try await Task.sleep(for: .seconds(60))
        }
        let replacementTask = Task<Void, Error> {
            try await Task.sleep(for: .seconds(60))
        }
        let foreground = UUID()
        harness.attempt.replaceTask(displacedTask)
        harness.attempt.activate(
            scanId: "old-scan",
            attemptGeneration: UUID(),
            foregroundGeneration: foreground
        )
        harness.queue.onRelease = {
            #expect(harness.attempt.task == nil)
            harness.attempt.replaceTask(replacementTask)
        }

        harness.coordinator.prepareForVisualAnalysis()

        #expect(displacedTask.isCancelled)
        #expect(!replacementTask.isCancelled)
        #expect(harness.attempt.task != nil)
        #expect(harness.queue.events == [
            .release(
                "old-scan",
                foreground,
                "live_scan_replaced_by_analyze"
            ),
            .retire(
                "old-scan",
                foreground,
                true,
                "live_scan_replaced_by_analyze"
            )
        ])

        harness.queue.onRelease = nil
        replacementTask.cancel()
        _ = await displacedTask.result
        _ = await replacementTask.result
    }

    @Test func nonVisualPreparationInstallsNonVisualPresentation() throws {
        let harness = InferenceSessionLifecycleHarness()
        let attempt = UUID()

        harness.coordinator.prepareForNonVisualAnalysis(
            scanId: "audio-scan",
            attemptGeneration: attempt
        )

        #expect(harness.state.isProcessing)
        let handoff = try #require(harness.presentation.transitionToQueue(
            scanId: "audio-scan",
            source: .prepared(attemptGeneration: attempt),
            isActiveAttemptCurrent: { _, _ in false },
            activeMediaItemCount: 4,
            activeVisualPhrases: ["Visual"],
            preparedVisualPhrases: ["Prepared"]
        ))
        #expect(handoff.scanningPhrases.isEmpty)
        #expect(!handoff.carriesLiveMedia)
    }

    @Test func activeVisualQueueHandoffPublishesOneCoherentState() {
        let harness = InferenceSessionLifecycleHarness()
        let attempt = UUID()
        let media = ActiveScanMedia(items: [.image("capture.webp")])
        harness.attempt.activate(
            scanId: "scan-a",
            attemptGeneration: attempt,
            foregroundGeneration: nil
        )
        harness.presentation.activate(
            scanId: "scan-a",
            attemptGeneration: attempt,
            modality: .visual
        )
        harness.state.setProcessing(true)
        harness.state.replaceActiveMedia(media)
        harness.state.replaceSpeciesData(
            inferenceSessionLifecycleSpeciesData(scanId: "scan-a")
        )

        let transitioned = harness.coordinator.transitionToQueue(
            scanId: "scan-a",
            source: .active(attemptGeneration: attempt),
            activeVisualPhrases: ["Studying wing pattern"]
        )

        #expect(transitioned)
        #expect(harness.state.scanningPhaseText == "Studying wing pattern")
        #expect(harness.state.queuedPresentationScanId == "scan-a")
        #expect(harness.state.activeMedia == media)
        #expect(harness.state.speciesData == nil)
        #expect(!harness.state.isProcessing)
        #expect(
            harness.attempt.recoverablePresentationScanId == "scan-a"
        )
        #expect(harness.presentation.hasVisualQueueHandoff(for: "scan-a"))
        #expect(harness.presentation.hasLiveMedia(for: "scan-a"))
    }

    @Test func cancellationRetiresOwnerAndReturnsToCleanIdleState() async {
        let harness = InferenceSessionLifecycleHarness()
        let attempt = UUID()
        let foreground = UUID()
        let task = Task<Void, Error> {
            try await Task.sleep(for: .seconds(60))
        }
        harness.attempt.replaceTask(task)
        harness.attempt.activate(
            scanId: "scan-a",
            attemptGeneration: attempt,
            foregroundGeneration: foreground
        )
        harness.presentation.activate(
            scanId: "scan-a",
            attemptGeneration: attempt,
            modality: .visual
        )
        harness.state.setProcessing(true)
        harness.state.setQueuedPresentationScanId("scan-a")
        harness.state.setEnrichmentLoading(true)
        harness.state.setLookalikesLoading(true)
        harness.state.replaceActiveMedia(
            ActiveScanMedia(items: [.image("capture.webp")])
        )
        harness.state.replaceSpeciesData(
            inferenceSessionLifecycleSpeciesData(scanId: "scan-a")
        )

        harness.coordinator.cancelActiveRequest(isUserInitiated: true)

        #expect(task.isCancelled)
        #expect(harness.attempt.activeScanId == nil)
        #expect(harness.attempt.recoverablePresentationScanId == nil)
        #expect(!harness.state.isProcessing)
        #expect(harness.state.queuedPresentationScanId == nil)
        #expect(harness.state.activeMedia.isEmpty)
        #expect(harness.state.speciesData == nil)
        #expect(!harness.state.isEnrichmentLoading)
        #expect(!harness.state.isLookalikesLoading)
        #expect(harness.queue.events == [
            .release("scan-a", foreground, "live_scan_cancelled_by_user"),
            .retire(
                "scan-a",
                foreground,
                true,
                "live_scan_cancelled_by_user"
            )
        ])
        _ = await task.result
    }

    @Test func historicalReplacementClearsDisplacedLoadersAndOwners() {
        let harness = InferenceSessionLifecycleHarness()
        let attempt = UUID()
        let foreground = UUID()
        harness.attempt.activate(
            scanId: "live-scan",
            attemptGeneration: attempt,
            foregroundGeneration: foreground
        )
        harness.attempt.setRecoverablePresentationScanId("live-scan")
        harness.presentation.beginFirstRenderMetric(
            scanId: "live-scan",
            startedAt: 42
        )
        harness.state.setQueuedPresentationScanId("live-scan")
        harness.state.setEnrichmentLoading(true)
        harness.state.setLookalikesLoading(true)
        let priorGeneration = harness.writes.generation

        #expect(harness.coordinator.beginHistoricalLoad())

        #expect(harness.attempt.activeScanId == nil)
        #expect(harness.attempt.recoverablePresentationScanId == nil)
        #expect(harness.state.isProcessing)
        #expect(harness.state.queuedPresentationScanId == nil)
        #expect(!harness.state.isEnrichmentLoading)
        #expect(!harness.state.isLookalikesLoading)
        #expect(harness.writes.generation == priorGeneration + 1)
        #expect(
            harness.presentation.consumeFirstRenderStart(
                scanId: "live-scan"
            ) == nil
        )
        #expect(harness.queue.events == [
            .release("live-scan", foreground, "persisted_scan_loaded"),
            .retire(
                "live-scan",
                foreground,
                true,
                "persisted_scan_loaded"
            )
        ])
    }

    @Test func authDrainAwaitsEveryCancellationIgnoringOwner() async {
        let harness = InferenceSessionLifecycleHarness()
        let attemptGate = InferenceSessionLifecycleGate()
        let hydrationGate = InferenceSessionLifecycleGate()
        let writeGate = InferenceSessionLifecycleGate()
        let attemptTask = Task<Void, Error> { await attemptGate.wait() }
        harness.attempt.replaceTask(attemptTask)
        harness.hydration.replaceTask(in: .live) {
            await hydrationGate.wait()
        }
        harness.writes.enqueueBackgroundWrite {
            await writeGate.wait()
        }
        await attemptGate.waitUntilStarted()
        await hydrationGate.waitUntilStarted()
        await writeGate.waitUntilStarted()
        harness.state.setQueuedPresentationScanId("scan-a")
        harness.state.replaceActiveMedia(
            ActiveScanMedia(items: [.image("capture.webp")])
        )

        harness.coordinator.beginAuthTransition()
        #expect(attemptTask.isCancelled)
        #expect(harness.writes.isAuthTransitionFenceActive)
        #expect(harness.hydration.snapshot.isAuthTransitionFenceActive)
        #expect(harness.state.queuedPresentationScanId == nil)
        #expect(harness.state.activeMedia.isEmpty)

        var drainStarted = false
        var drainFinished = false
        let drain = Task { @MainActor in
            drainStarted = true
            await harness.coordinator.awaitAuthTransitionQuiescence()
            drainFinished = true
        }
        while !drainStarted { await Task.yield() }
        #expect(!drainFinished)

        await attemptGate.release()
        await Task.yield()
        #expect(!drainFinished)
        await hydrationGate.release()
        await Task.yield()
        #expect(!drainFinished)
        await writeGate.release()
        await drain.value

        #expect(drainFinished)
        #expect(harness.attempt.task == nil)
        #expect(harness.hydration.snapshot.activeTaskCount == 0)
        #expect(harness.writes.snapshot.active == 0)

        harness.coordinator.finishAuthTransition()
        #expect(!harness.writes.isAuthTransitionFenceActive)
        #expect(!harness.hydration.snapshot.isAuthTransitionFenceActive)
    }

    @Test func authDrainAlsoAwaitsAnAlreadyDisplacedInferenceTask() async {
        let harness = InferenceSessionLifecycleHarness()
        let attemptGate = InferenceSessionLifecycleGate()
        let displacedTask = Task<Void, Error> {
            await attemptGate.wait()
        }
        harness.attempt.replaceTask(displacedTask)
        harness.attempt.activate(
            scanId: nil,
            attemptGeneration: UUID(),
            foregroundGeneration: nil
        )
        await attemptGate.waitUntilStarted()

        harness.coordinator.prepareForVisualAnalysis()
        #expect(displacedTask.isCancelled)
        #expect(harness.attempt.task == nil)

        harness.coordinator.beginAuthTransition()
        var drainFinished = false
        let drain = Task { @MainActor in
            await harness.coordinator.awaitAuthTransitionQuiescence()
            drainFinished = true
        }
        await Task.yield()
        #expect(!drainFinished)

        await attemptGate.release()
        await drain.value

        #expect(drainFinished)
        harness.coordinator.finishAuthTransition()
    }

}
