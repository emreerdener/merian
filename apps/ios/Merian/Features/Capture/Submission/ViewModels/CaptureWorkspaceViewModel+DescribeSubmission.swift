import SwiftData

extension CaptureWorkspaceViewModel {

    // MARK: - Submit Describe (entry point from DescribeInputView)

    /// Routes the observation based on what else is staged.
    ///
    /// - **Reanalysis**: adds or updates one supplementary description beyond the evidence budget.
    /// - **Multi-capture mode**: always stages the description so the user can compose up to
    ///   two total items before tapping Identify.
    /// - **Single-capture with images staged**: stages the description into
    ///   `stagedCapture.observationContexts` so the toolbar owns the eventual submit.
    /// - **Single-capture with nothing else staged**: routes immediately through the solo
    ///   non-visual submission path unless explicit confirmation is enabled.
    ///
    /// Includes a 1.5s debounce to prevent duplicate enqueuing on rapid physical taps.
    @discardableResult
    func submitDescribe(
        observationContext: ObservationContext,
        modelContext: ModelContext
    ) async -> Bool {
        // Prevent rapid duplicate taps from spawning identical offline queue records
        let now = CFAbsoluteTimeGetCurrent()
        guard (now - (stagedCapture.lastSubmitTime ?? 0)) > 1.5 else { return false }
        stagedCapture.lastSubmitTime = now

        guard !observationContext.isEmpty else { return false }

        // StagedObservationContext owns the submission-order timestamp. Keep
        // ObservationContext itself as text-only domain data so that capture
        // chronology never leaks into the durable cloud representation.
        let stagedContext = observationContext

        let isMultiCaptureEnabled = isMultiCaptureFunctionallyEnabled
        let requiresScanConfirmation = diContainer.appSettings.requiresScanConfirmation
        let isRefining = baseRefinementContext != nil

        if isRefining {
            guard !isStagingRefinement, !isCheckingScanAdmission else { return false }
            let result = stagePendingDescribeDraftForActiveSubmission(stagedContext)
            if result == .rejected { presentDescriptionStagingError() }
            return result == .staged
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
                    return await submitDescribeSolo(
                        observationContext: stagedContext,
                        modelContext: modelContext,
                        targetEradicationScanId: targetEradicationScanId
                    )
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
    func stagePendingDescribeDraftForActiveSubmission(
        _ observationContext: ObservationContext
    ) -> CaptureDescriptionStagingResult {
        guard !observationContext.isEmpty else { return .emptyDraft }

        let stagedContext = observationContext

        if baseRefinementContext != nil {
            guard stagedCapture.canStageRefinementDescription else { return .rejected }
            if let index = stagedCapture.refinementSupplementIndex {
                stagedCapture.observationContexts[index].context = stagedContext
            } else {
                stagedCapture.observationContexts.append(StagedObservationContext(
                    context: stagedContext,
                    isRefinementSupplement: true
                ))
            }
            return .staged
        }

        if let index = stagedCapture.observationContexts.indices.last {
            let addedAt = stagedCapture.observationContexts[index].addedAt
            stagedCapture.observationContexts[index] = StagedObservationContext(
                context: stagedContext,
                addedAt: addedAt
            )
            return .staged
        }

        guard stagedCapture.availableSlots(limit: stagedCaptureLimit) > 0 else { return .rejected }
        stagedCapture.observationContexts.append(StagedObservationContext(context: stagedContext))
        return .staged
    }

    /// The toolbar must not clear a rejected draft or submit evidence without it.
    /// Synchronous preparation also snapshots text before asynchronous admission begins.
    func prepareActiveStagedSubmission(descriptionDraft: inout ObservationContext) -> Bool {
        guard !isCheckingScanAdmission, !isStagingRefinement else { return false }
        switch stagePendingDescribeDraftForActiveSubmission(descriptionDraft) {
        case .emptyDraft:
            return true
        case .staged:
            descriptionDraft = ObservationContext()
            return true
        case .rejected:
            presentDescriptionStagingError()
            return false
        }
    }

    private func presentDescriptionStagingError() {
        offlineToastMessage = .error("Your description couldn’t be added. Please try again.")
    }

    // MARK: - Solo Describe Path (description only, no images)

    /// Routes a solo description through the shared non-visual pipeline.
    ///
    /// Call order (online):
    /// 1. Snapshot the `ObservationContext` (value type — no race risk).
    /// 2. Generate a stable `scanId` and durable foreground generation.
    /// 3. Queue the zero-byte staged job with cached telemetry before awaiting
    ///    optional environment enrichment.
    /// 4. Give the pinned context task at most 150 ms for the live request.
    /// 5. Atomically claim the generation and fire
    ///    `InferenceEngine.analyzeNonVisual`.
    ///
    /// Call order (offline):
    /// 1. Enqueue via `OfflineQueueManager.enqueueNonVisualCapture` with cached GPS telemetry.
    ///    WeatherKit backfill is deferred to `dispatchInferenceDownloadTask` on retry.
    /// 2. Show "No network connection. Queued for analysis." toast.
    @discardableResult
    func submitDescribeSolo(
        observationContext: ObservationContext,
        modelContext: ModelContext,
        targetEradicationScanId: String? = nil
    ) async -> Bool {
        guard !observationContext.isEmpty else { return false }
        return await submitNonVisualCapture(
            audioFileNames: [],
            observationContexts: [observationContext],
            mediaTimeline: [.description(observationContext)],
            modelContext: modelContext,
            targetEradicationScanId: targetEradicationScanId
        )
    }
}
