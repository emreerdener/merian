import SwiftData
import SwiftUI

extension CaptureWorkspaceViewModel {

    // MARK: - Submit Describe (entry point from DescribeInputView)

    /// Routes the observation based on what else is staged.
    ///
    /// - **Multi-capture mode**: always stages the description so the user can compose up to
    ///   two total items before tapping Identify.
    /// - **Single-capture with images staged**: stages the description into
    ///   `stagedCapture.observationContexts` so the toolbar owns the eventual submit.
    /// - **Single-capture with nothing else staged**: routes immediately through the solo
    ///   non-visual submission path unless explicit confirmation is enabled.
    ///
    /// Includes a 1.5s debounce to prevent duplicate enqueuing on rapid physical taps.
    @discardableResult
    func submitDescribe(observationContext: ObservationContext, modelContext: ModelContext) -> Bool {
        // Prevent rapid duplicate taps from spawning identical offline queue records
        let now = CFAbsoluteTimeGetCurrent()
        guard (now - (stagedCapture.lastSubmitTime ?? 0)) > 1.5 else { return false }
        stagedCapture.lastSubmitTime = now

        guard !observationContext.isEmpty else { return false }

        // The observationContext originates from a long-lived @State binding in
        // CaptureWorkspaceView. We must mint a brand new generation timestamp here right
        // as the user formally submits it to staging to guarantee chronological accuracy.
        var stagedContext = observationContext
        stagedContext.addedAt = Date()

        let isMultiCaptureEnabled = isMultiCaptureFunctionallyEnabled
        let requiresScanConfirmation = diContainer.appSettings.requiresScanConfirmation
        let isRefining = baseRefinementContext != nil

        if isRefining {
            guard stagedCapture.availableSlots(limit: stagedCaptureLimit) > 0 else { return false }
            stagedCapture.observationContexts.append(StagedObservationContext(context: stagedContext))
            return true
        } else if isMultiCaptureEnabled {
            guard stagedCapture.availableSlots(limit: stagedCaptureLimit) > 0 else { return false }
            stagedCapture.observationContexts.append(StagedObservationContext(context: stagedContext))
            return true
        } else {
            if stagedCapture.hasVisualMedia || !stagedCapture.audios.isEmpty || !stagedCapture.observationContexts.isEmpty {
                // Already-staged media composes through the toolbar.
                // The ActiveScanToolbar's Identify button owns submission in this state.
                stagedCapture.observationContexts = [StagedObservationContext(context: stagedContext)]
                return true
            } else {
                if requiresScanConfirmation {
                    // Stage as a solo node so the user confirms via Identify before submitting.
                    // submitStagedCapture routes description-only back through submitDescribeSolo.
                    stagedCapture.observationContexts = [StagedObservationContext(context: stagedContext)]
                } else {
                    let targetEradicationScanId = baseRefinementContext?.scanId
                    baseRefinementContext = nil
                    refinementSubjectId = nil
                    submitDescribeSolo(observationContext: stagedContext, modelContext: modelContext, targetEradicationScanId: targetEradicationScanId)
                }
                return true
            }
        }
    }

    /// Consumes any live Describe text before the active staged toolbar submits.
    ///
    /// The bottom toolbar can submit already-staged media while the Describe page is still
    /// showing a live text draft. Capture that draft into the staged payload when possible
    /// so the submitted analysis owns it and the input can reset cleanly afterward.
    @discardableResult
    func stagePendingDescribeDraftForActiveSubmission(_ observationContext: ObservationContext) -> Bool {
        guard !observationContext.isEmpty else { return false }

        var stagedContext = observationContext
        stagedContext.addedAt = Date()

        if let index = stagedCapture.observationContexts.indices.last {
            let addedAt = stagedCapture.observationContexts[index].addedAt
            stagedCapture.observationContexts[index] = StagedObservationContext(
                context: stagedContext,
                addedAt: addedAt
            )
            return true
        }

        guard stagedCapture.availableSlots(limit: stagedCaptureLimit) > 0 else { return false }
        stagedCapture.observationContexts.append(StagedObservationContext(context: stagedContext))
        return true
    }

    // MARK: - Solo Describe Path (description only, no images)

    /// Routes a solo description through the shared non-visual pipeline.
    ///
    /// Call order (online):
    /// 1. Snapshot the `ObservationContext` (value type — no race risk).
    /// 2. Generate a stable `scanId` and durable foreground generation.
    /// 3. Resolve full telemetry from the environment context manager.
    /// 4. Queue the zero-byte staged job before opening the insight sheet.
    /// 5. Atomically claim the generation and fire
    ///    `InferenceEngine.analyzeNonVisual`.
    ///
    /// Call order (offline):
    /// 1. Reset `InferenceEngine` state (ensures a clean slate for the next online attempt).
    /// 2. Enqueue via `OfflineQueueManager.enqueueNonVisualCapture` with cached GPS telemetry.
    ///    WeatherKit backfill is deferred to `dispatchInferenceDownloadTask` on retry.
    /// 3. Show "No network connection. Queued for upload." toast.
    func submitDescribeSolo(observationContext: ObservationContext, modelContext: ModelContext, targetEradicationScanId: String? = nil) {
        guard !observationContext.isEmpty else { return }
        submitNonVisualCapture(
            audioFileNames: [],
            observationContexts: [observationContext],
            mediaTimeline: [.description(observationContext)],
            modelContext: modelContext,
            targetEradicationScanId: targetEradicationScanId
        )
    }
}
