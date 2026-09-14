import Foundation

/// Coordinates synchronous session replacement and Auth-transition ordering.
///
/// Every mutable value and task remains owned by its focused coordinator. This
/// type only sequences those owners so new scans, live analysis, recovered
/// results, cancellation, queue handoff, historical loading, and Auth
/// quiescence cannot drift apart. It resolves no networking, persistence,
/// logging, or singleton dependency; durable queue actions stay behind the
/// injected attempt owner.
@MainActor
final class InferenceSessionLifecycleCoordinator {
    private let attemptCoordinator: InferenceLiveAttemptCoordinator
    private let hydrationCoordinator: InferenceHydrationCoordinator
    private let writeCoordinator: InferenceWriteCoordinator
    private let localAnalysisCoordinator: InferenceLocalAnalysisCoordinator
    private let presentationCoordinator: InferencePresentationCoordinator
    private let presentationState: InferencePresentationState

    init(
        attemptCoordinator: InferenceLiveAttemptCoordinator,
        hydrationCoordinator: InferenceHydrationCoordinator,
        writeCoordinator: InferenceWriteCoordinator,
        localAnalysisCoordinator: InferenceLocalAnalysisCoordinator,
        presentationCoordinator: InferencePresentationCoordinator,
        presentationState: InferencePresentationState
    ) {
        self.attemptCoordinator = attemptCoordinator
        self.hydrationCoordinator = hydrationCoordinator
        self.writeCoordinator = writeCoordinator
        self.localAnalysisCoordinator = localAnalysisCoordinator
        self.presentationCoordinator = presentationCoordinator
        self.presentationState = presentationState
    }

    func beginAuthTransition() {
        guard writeCoordinator.beginAuthTransitionFence() else { return }
        _ = hydrationCoordinator.beginAuthTransitionFence()
        attemptCoordinator.invalidateFollowUpAuthorization()
        attemptCoordinator.cancelAllTasks()
        localAnalysisCoordinator.cancel()
        presentationCoordinator.clearForAuthTransitionAdmission()
        attemptCoordinator.setRecoverablePresentationScanId(nil)
        presentationState.clearForAuthTransition(
            defaultScanningPhrase: ScanningPhraseCoordinator.genericPhrases[0]
        )
        writeCoordinator.resetPresentationWrites()
    }

    func awaitAuthTransitionQuiescence() async {
        guard writeCoordinator.isAuthTransitionFenceActive else { return }

        await attemptCoordinator.awaitQuiescence()
        await hydrationCoordinator.awaitQuiescence()
        await writeCoordinator.awaitQuiescence()

        attemptCoordinator.clearCurrentTask()
        localAnalysisCoordinator.cancel()
        presentationCoordinator.finishAuthTransitionQuiescence()
    }

    func finishAuthTransition() {
        hydrationCoordinator.finishAuthTransitionFence()
        writeCoordinator.finishAuthTransitionFence()
    }

    func prepareForNewScan(
        scanId: String?,
        attemptGeneration: UUID?,
        modality: InferencePresentationCoordinator.Modality
    ) {
        guard !writeCoordinator.isAuthTransitionFenceActive else { return }
        prepareForNewScanUnchecked(
            scanId: scanId,
            attemptGeneration: attemptGeneration,
            modality: modality
        )
    }

    /// Preserves the visual path's replacement order after pipeline admission.
    func prepareForVisualAnalysis() {
        guard !writeCoordinator.isAuthTransitionFenceActive else { return }
        attemptCoordinator.invalidateActiveAttempt(
            resumeBackground: true,
            reason: "live_scan_replaced_by_analyze"
        )
        hydrationCoordinator.cancelAllTasks()
        localAnalysisCoordinator.cancel()
        // Admission has committed to a replacement. Discard the displaced
        // ephemeral owner and render timestamp before the new owner is
        // installed so a same-scan retry cannot consume stale timing state.
        presentationCoordinator.reset()
        writeCoordinator.resetPresentationWrites()

        // Clear before a cancelled hydration defer can resume on MainActor and
        // interfere with loaders published for the replacement presentation.
        presentationState.clearLoadingState()
    }

    /// Preserves the historical nonvisual path's pre-reset cancellation pass.
    func prepareForNonVisualAnalysis(
        scanId: String?,
        attemptGeneration: UUID
    ) {
        guard !writeCoordinator.isAuthTransitionFenceActive else { return }
        attemptCoordinator.cancelCurrentTask()
        hydrationCoordinator.cancelAllTasks()
        localAnalysisCoordinator.cancel()
        prepareForNewScanUnchecked(
            scanId: scanId,
            attemptGeneration: attemptGeneration,
            modality: .nonVisual
        )
    }

    func publishSuccessfulResult(
        _ speciesData: SpeciesData,
        persistedMediaItems: [MediaItem]?
    ) {
        presentationCoordinator.clearForPublishedResult()
        attemptCoordinator.setRecoverablePresentationScanId(nil)
        presentationState.publishSuccessfulResult(
            speciesData,
            persistedMediaItems: persistedMediaItems
        )
    }

    @discardableResult
    func commitRecoveredBackgroundResult(
        for scanId: String,
        replacingAttemptGeneration: UUID,
        expectedForegroundGeneration: UUID?,
        speciesData: SpeciesData
    ) -> Bool {
        guard attemptCoordinator.canCommitRecoveredBackgroundResult(
            scanId: scanId,
            replacingAttemptGeneration: replacingAttemptGeneration,
            expectedForegroundGeneration: expectedForegroundGeneration
        ) else {
            return false
        }

        // Relinquish and cancel the exact displaced task before publication so
        // a synchronous observer can safely install a replacement. Its defer
        // and error path no longer own the cleared attempt identity.
        attemptCoordinator.cancelAndClearActiveAttempt()
        localAnalysisCoordinator.cancel()
        publishSuccessfulResult(speciesData, persistedMediaItems: nil)
        return true
    }

    @discardableResult
    func commitRecoveredQueuedResult(
        for scanId: String,
        speciesData: SpeciesData
    ) -> Bool {
        guard attemptCoordinator.recoverablePresentationScanId == scanId,
              speciesData.scanId?.caseInsensitiveCompare(scanId)
                == .orderedSame,
              attemptCoordinator.activeScanId == nil
                || attemptCoordinator.activeScanId == scanId else {
            return false
        }

        attemptCoordinator.cancelAndClearActiveAttempt()
        attemptCoordinator.setRecoverablePresentationScanId(nil)
        localAnalysisCoordinator.cancel()
        publishSuccessfulResult(speciesData, persistedMediaItems: nil)
        return true
    }

    @discardableResult
    func commitRecoveredQueuedRecord(
        for scanId: String,
        recordScanId: String,
        loadRecord: () -> Void
    ) -> Bool {
        guard attemptCoordinator.recoverablePresentationScanId == scanId,
              recordScanId == scanId,
              attemptCoordinator.activeScanId == nil
                || attemptCoordinator.activeScanId == scanId else {
            return false
        }

        attemptCoordinator.setRecoverablePresentationScanId(nil)
        loadRecord()
        return true
    }

    func finishLivePipelinePresentation(attemptGeneration: UUID) {
        presentationState.setProcessing(false)
        presentationCoordinator.finishActivePresentation(
            attemptGeneration: attemptGeneration
        )
        localAnalysisCoordinator.cancel()
    }

    func rebindFirstRenderMetric(
        from sourceScanId: String,
        to resultScanId: String
    ) {
        presentationCoordinator.rebindFirstRenderMetric(
            from: sourceScanId,
            to: resultScanId
        )
    }

    func transitionToQueue(
        scanId: String,
        source: InferencePresentationCoordinator.QueueSource,
        activeVisualPhrases: [String]
    ) -> Bool {
        guard let handoff = presentationCoordinator.transitionToQueue(
            scanId: scanId,
            source: source,
            isActiveAttemptCurrent: { [attemptCoordinator] scanId, generation in
                attemptCoordinator.isLocalAttemptCurrent(
                    scanId: scanId,
                    attemptGeneration: generation
                )
            },
            activeMediaItemCount: presentationState.activeMedia.totalItems,
            activeVisualPhrases: activeVisualPhrases,
            preparedVisualPhrases: ScanningPhraseCoordinator.genericPhrases
        ) else {
            return false
        }

        presentationState.beginQueueHandoff(
            scanningPhrases: handoff.scanningPhrases
        )
        attemptCoordinator.setRecoverablePresentationScanId(handoff.scanId)
        presentationState.setQueuedPresentationScanId(handoff.scanId)
        localAnalysisCoordinator.cancel(resetPhraseCoordinator: false)
        presentationState.finishQueueHandoff()
        return true
    }

    func dismissAnalyzingPresentation() {
        presentationCoordinator.reset()
        attemptCoordinator.setRecoverablePresentationScanId(nil)
        localAnalysisCoordinator.cancel()
        presentationState.dismissAnalyzingPresentation(
            defaultScanningPhrase: ScanningPhraseCoordinator.genericPhrases[0]
        )
    }

    func cancelActiveRequest(isUserInitiated: Bool) {
        attemptCoordinator.invalidateActiveAttempt(
            resumeBackground: true,
            reason: isUserInitiated
                ? "live_scan_cancelled_by_user"
                : "live_scan_cancelled"
        )
        presentationState.beginCancellation()
        hydrationCoordinator.cancelAllTasks()
        localAnalysisCoordinator.cancel()
        writeCoordinator.resetPresentationWrites()
        attemptCoordinator.setRecoverablePresentationScanId(nil)
        presentationCoordinator.reset()
        presentationState.finishCancellation(
            defaultScanningPhrase: ScanningPhraseCoordinator.genericPhrases[0]
        )
    }

    @discardableResult
    func beginHistoricalLoad() -> Bool {
        guard !writeCoordinator.isAuthTransitionFenceActive else { return false }
        attemptCoordinator.invalidateActiveAttempt(
            resumeBackground: true,
            reason: "persisted_scan_loaded"
        )
        attemptCoordinator.setRecoverablePresentationScanId(nil)
        presentationCoordinator.reset()

        // Clear displaced loaders before invalidating their generation. Their
        // guarded cleanup is no longer authorized after cancellation.
        presentationState.beginHistoricalLoad()
        hydrationCoordinator.cancelAllTasks()
        localAnalysisCoordinator.cancel()
        writeCoordinator.resetPresentationWrites()
        return true
    }

    func handleApplicationActiveStateChange(isActive: Bool) {
        let canResume = presentationState.isProcessing
            && presentationCoordinator.isActiveVisual(
                attemptGeneration: attemptCoordinator.activeAttemptGeneration
            )
        if isActive {
            localAnalysisCoordinator.resumeAfterInactivity(
                canResume: canResume
            )
            return
        }
        localAnalysisCoordinator.pauseForInactivity(canResume: canResume)
    }

    private func prepareForNewScanUnchecked(
        scanId: String?,
        attemptGeneration: UUID?,
        modality: InferencePresentationCoordinator.Modality
    ) {
        attemptCoordinator.invalidateActiveAttempt(
            resumeBackground: true,
            reason: "live_scan_replaced"
        )
        hydrationCoordinator.cancelAllTasks()
        hydrationCoordinator.resetEnrichmentRateLimit()
        localAnalysisCoordinator.cancel()
        writeCoordinator.resetPresentationWrites()

        attemptCoordinator.setActiveScanId(nil)
        attemptCoordinator.setRecoverablePresentationScanId(nil)
        presentationCoordinator.prepare(
            scanId: scanId,
            attemptGeneration: attemptGeneration,
            modality: modality
        )
        presentationState.prepareForNewScan(
            defaultScanningPhrase: ScanningPhraseCoordinator.genericPhrases[0]
        )
    }
}
