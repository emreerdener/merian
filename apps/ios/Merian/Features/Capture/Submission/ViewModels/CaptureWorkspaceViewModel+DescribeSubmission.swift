import SwiftData

extension CaptureWorkspaceViewModel {

    // MARK: - Submit Describe (entry point from DescribeInputView)

    /// The initial Describe action stages the shared note by default. Explicit
    /// auto-submit sends a text-only draft through the same durable queue path.
    /// Once review exists, its toolbar owns submission and the root editor stays live.
    @discardableResult
    func submitDescribe(
        observationContext: ObservationContext,
        modelContext: ModelContext
    ) async -> Bool {
        guard !isDraftMutationLocked, !observationContext.isEmpty else { return false }
        let submitImmediately = diContainer.appSettings.autoSubmitScans
            && stagedCapture.isEmpty && baseRefinementContext == nil
        updateDescriptionDraft(observationContext)
        isReviewActive = true
        synchronizeSharedDescription()
        if submitImmediately {
            await submitStagedCapture(modelContext: modelContext)
        }
        return true
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

        stagedCapture.observationContexts.append(StagedObservationContext(context: stagedContext))
        return .staged
    }

    /// The toolbar must not clear a rejected draft or submit evidence without it.
    /// Synchronous preparation also snapshots text before asynchronous admission begins.
    func prepareActiveStagedSubmission(descriptionDraft: inout ObservationContext) -> Bool {
        guard !isDraftMutationLocked, isDraftReadyForSubmission else { return false }
        switch stagePendingDescribeDraftForActiveSubmission(descriptionDraft) {
        case .emptyDraft:
            return true
        case .staged:
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
        userPerceivedStart: CFAbsoluteTime,
        targetEradicationScanId: String? = nil
    ) async -> Bool {
        guard !observationContext.isEmpty else { return false }
        return await submitNonVisualCapture(
            audioFileNames: [],
            observationContexts: [observationContext],
            mediaTimeline: [.description(observationContext)],
            modelContext: modelContext,
            targetEradicationScanId: targetEradicationScanId,
            userPerceivedStart: userPerceivedStart
        )
    }
}
