import SwiftData
import SwiftUI

extension InsightSheetViewModel {
    // MARK: - SwiftData Operations

    func fetchActiveLocalRecord(modelContext: ModelContext) -> LocalScanRecord? {
        guard let activeLocalRecordId else { return nil }
        return fetchLocalRecord(scanId: activeLocalRecordId, modelContext: modelContext)
    }

    func fetchLocalRecord(scanId: String, modelContext: ModelContext) -> LocalScanRecord? {
        var descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.id == scanId }
        )
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    func eradicateCurrentScan(
        expectedScanId: String,
        expectedGeneration: UInt64,
        modelContext: ModelContext,
        inferenceEngine: InferenceEngine,
        dismiss: DismissAction
    ) {
        guard let targetId = inferenceEngine.speciesData?.scanId,
              targetId.caseInsensitiveCompare(expectedScanId) == .orderedSame,
              isPresentingLocalRecord(
                  scanId: expectedScanId,
                  generation: expectedGeneration
              ) else {
            return
        }

        if let record = fetchLocalRecord(scanId: expectedScanId, modelContext: modelContext),
           record.id.caseInsensitiveCompare(targetId) == .orderedSame {
            dependencies.errorFeedback()
            activeLocalRecord = nil
            activeLocalRecordId = nil
            toolbarRecordSnapshot = nil
            state.showBottomBarTools = false
            state.showDeleteConfirmation = false
            state.showNewCollectionAlert = false
            dependencies.eradicateScan(record, modelContext)
            dismiss()
        }
    }

    func toggleScanInCollection(
        _ collection: ScanCollection,
        modelContext: ModelContext,
        expectedScanId: String? = nil,
        expectedGeneration: UInt64? = nil
    ) {
        if let expectedScanId,
           !isPresentingLocalRecord(
               scanId: expectedScanId,
               generation: expectedGeneration
           ) {
            return
        }
        guard let record = fetchActiveLocalRecord(modelContext: modelContext) else { return }
        if let expectedScanId,
           record.id.caseInsensitiveCompare(expectedScanId) != .orderedSame {
            return
        }

        var updatedCollections = record.collections ?? []
        let actionMessage: String

        if updatedCollections.contains(where: { $0.id == collection.id }) {
            updatedCollections.removeAll(where: { $0.id == collection.id })
            actionMessage = "Removed from \(collection.name)"
        } else {
            updatedCollections.append(collection)
            actionMessage = "Added to \(collection.name)"
        }

        record.collections = updatedCollections
        guard saveInsightMutation(
            modelContext,
            failureMessage: "Could not update collection. Please try again.",
            logContext: "toggle scan collection"
        ) else {
            dependencies.errorFeedback()
            return
        }

        state.toastMessage = .success(actionMessage)
        activeLocalRecord = record
        toolbarRecordSnapshot = InsightToolbarRecordSnapshot(record: record)
        dependencies.enqueueCollectionSync()
        dependencies.selectionFeedback()
    }

    @discardableResult
    private func saveInsightMutation(
        _ modelContext: ModelContext,
        failureMessage: String?,
        logContext: String
    ) -> Bool {
        do {
            try modelContext.save()
            return true
        } catch {
            modelContext.rollback()
            MerianLog.data.error("InsightSheetViewModel: failed to save \(logContext, privacy: .public): \(error, privacy: .private)")
            if let failureMessage {
                state.toastMessage = .error(failureMessage)
            }
            return false
        }
    }

// Removed createNewCollection as this logic was extracted into NewCollectionAlertModifier

    @discardableResult
    func fetchLocalRecord(for scanId: String, modelContext: ModelContext) -> Bool {
        if let record = fetchLocalRecord(scanId: scanId, modelContext: modelContext) {
            bindPresentedRecord(record, modelContext: modelContext)
            return true
        }

        clearPresentedRecordBinding(ifNotMatching: scanId)
        return false
    }

    @discardableResult
    func bindPresentedScan(
        scanId: String,
        modelContext: ModelContext,
        inferenceEngine: InferenceEngine
    ) -> Bool {
        var descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.id == scanId }
        )
        descriptor.fetchLimit = 1

        guard let record = (try? modelContext.fetch(descriptor))?.first else {
            invalidateScanBoundPresentationState()
            return false
        }

        // Value-only routes are resolved by LocalScanInsightLoader before this
        // view mounts. Keep this fallback for legacy/direct callers, but do not
        // cancel and restart the exact hydration that the loader just began.
        let engineAlreadyPresentsRecord =
            inferenceEngine.activeScanId?
                .caseInsensitiveCompare(record.id) == .orderedSame &&
            inferenceEngine.speciesData?.scanId?
                .caseInsensitiveCompare(record.id) == .orderedSame
        if !engineAlreadyPresentsRecord {
            inferenceEngine.load(from: record)
        }
        bindPresentedRecord(record, modelContext: modelContext)
        return true
    }

    /// Binds a queued route snapshot while treating a completed local record with the same
    /// identity as authoritative. Navigation routes retain value snapshots by design, so this
    /// prevents a destination reappearance from resurrecting queued UI after completion.
    @discardableResult
    func bindQueuedPresentationPreferringCompletedRecord(
        _ queuedScan: QueuedScanContext,
        modelContext: ModelContext,
        inferenceEngine: InferenceEngine
    ) -> Bool {
        // A retained NavigationPath value may be rebound after this destination already
        // promoted the matching completion. Treat that rebind as idempotent: invalidating
        // and promoting again would briefly hide result actions and reset scan-bound state.
        if self.inferenceEngine === inferenceEngine,
           queuedContext == nil,
           isPresentingLocalRecord(scanId: queuedScan.id) {
            return true
        }

        bindQueuedPresentation(queuedScan)
        return promoteQueuedScanIfLocalRecordExists(
            scanId: queuedScan.id,
            modelContext: modelContext,
            inferenceEngine: inferenceEngine
        )
    }

    @discardableResult
    func promoteQueuedScanIfLocalRecordExists(
        scanId: String,
        modelContext: ModelContext,
        inferenceEngine: InferenceEngine
    ) -> Bool {
        guard queuedContext?.id
            .caseInsensitiveCompare(scanId) == .orderedSame else {
            return false
        }
        var descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.id == scanId }
        )
        descriptor.fetchLimit = 1

        guard let record = (try? modelContext.fetch(descriptor))?.first else {
            return false
        }

        // Release queued routing before binding the completed record so local-record identity,
        // Field Notes handoff, share-state hydration, and viewed-state persistence all resolve
        // against the result presentation rather than the now-retired queue snapshot.
        invalidateScanBoundPresentationState()
        queuedContext = nil
        inferenceEngine.load(from: record)
        bindPresentedRecord(record, modelContext: modelContext)

        if let scientificName = inferenceEngine.speciesData?.scientificName {
            loadPreferredCommonName(for: scientificName, modelContext: modelContext)
        }
        evaluateVoiceOverAndCelebration(inferenceEngine: inferenceEngine)
        MerianLog.data.debug(
            "InsightSheetViewModel.promoteQueuedScanIfLocalRecordExists: promoted scanId=\(scanId, privacy: .private)"
        )
        return true
    }

    func bindPresentedRecord(_ record: LocalScanRecord, modelContext: ModelContext) {
        let recordId = record.id.trimmingCharacters(in: .whitespacesAndNewlines)
        let cachedScanIds = [
            activeLocalRecord?.id,
            activeLocalRecordId,
            toolbarRecordSnapshot?.scanId
        ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        if cachedScanIds.contains(where: {
            $0.caseInsensitiveCompare(recordId) != .orderedSame
        }) {
            invalidateScanBoundPresentationState()
        }

        activeLocalRecord = record
        activeLocalRecordId = record.id
        toolbarRecordSnapshot = InsightToolbarRecordSnapshot(record: record)
        cachedActiveMedia = record.capturedMediaSnapshot.activeScanMedia
        refreshSharedExploreStateFromLocalCache(scanId: record.id)
        syncFieldNotesFromCurrentScan(modelContext: modelContext)
        markRecordViewedIfAppropriate(modelContext: modelContext)
    }

    func bindQueuedPresentation(_ context: QueuedScanContext) {
        if queuedContext?.id.caseInsensitiveCompare(context.id) == .orderedSame {
            queuedContext = context
            cachedActiveMedia = context.activeScanMedia
            return
        }

        invalidateScanBoundPresentationState()
        queuedContext = context
        cachedActiveMedia = context.activeScanMedia
    }

    /// Resolves the durable queue row for a live sheet that relinquished its
    /// foreground request after connectivity changed. Snapshotting immediately
    /// keeps the presentation safe if background recovery later deletes the row.
    @discardableResult
    func bindQueuedPresentationIfAvailable(
        scanId: String,
        modelContext: ModelContext
    ) -> Bool {
        var descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        descriptor.fetchLimit = 1
        guard let scan = (try? modelContext.fetch(descriptor))?.first else {
            return false
        }
        bindQueuedPresentation(QueuedScanContext(from: scan))
        return true
    }

    func releaseQueuedPresentation(expectedScanId: String) {
        guard queuedContext?.id
            .caseInsensitiveCompare(expectedScanId) == .orderedSame else {
            return
        }
        invalidateScanBoundPresentationState()
        queuedContext = nil
    }

    /// Removes scan-bound UI state when an asynchronous record lookup targets a
    /// different scan than the one currently cached. A transient miss for the
    /// same scan preserves its snapshot while SwiftData contexts propagate.
    private func clearPresentedRecordBinding(ifNotMatching scanId: String) {
        let targetScanId = scanId.trimmingCharacters(in: .whitespacesAndNewlines)
        let cachedScanIds = [
            activeLocalRecord?.id,
            activeLocalRecordId,
            toolbarRecordSnapshot?.scanId
        ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }

        guard cachedScanIds.contains(where: {
            $0.caseInsensitiveCompare(targetScanId) != .orderedSame
        }) else {
            return
        }

        invalidateScanBoundPresentationState()
    }

    private func invalidateScanBoundPresentationState() {
        cancelDelayedExploreOnboardingPresentation()
        scanBoundActionGeneration &+= 1
        sharingOperations.invalidate()
        invalidateFieldTripScanContributions()
        activeLocalRecord = nil
        activeLocalRecordId = nil
        toolbarRecordSnapshot = nil
        cachedActiveMedia = nil
        boundFieldNotesScanId = nil
        state.showBottomBarTools = false
        state.showDeleteConfirmation = false
        state.showMediaSaveAlert = false
        state.lastMediaSaveResult = MediaSaveResult()
        state.isSavingMedia = false
        state.showNewCollectionAlert = false
        state.isFieldNotesSheetPresented = false
        state.fieldNotesPresentationScanId = nil
        state.fieldNotesPresentationGeneration = nil
        state.isFlagIssuePresented = false
        state.isInsightChatSheetPresented = false
        state.isCandidateSwipePresented = false
        state.candidateSwipePresentationSource = .standard
        state.candidateSwipePresentationScanId = nil
        state.candidateSwipePresentationGeneration = nil
        state.candidateSwipeEnginePresentationGeneration = nil
        state.isNamePickerPresented = false
        state.isSafariPresented = false
        state.selectedWikiURL = nil
        state.safariPresentationScanId = nil
        state.safariPresentationGeneration = nil
        state.preferredCommonName = nil
        state.isAudioBoostEnabled = false
        state.audioBoostActionToken = nil
        state.isSharingToExplore = false
        state.isUpdatingExplorePostContent = false
        state.isUpdatingExploreFieldNotes = false
        state.isRequestingCommunityIdentification = false
        state.fieldNotesText = ""
        state.dismissedFieldNotesCardScanId = nil
        state.sharedExplorePostId = nil
        state.sharedCommunityIdentificationRequestId = nil
        state.sharedCommunityIdentificationStatus = nil
        state.isExploreFeedVisible = false
        state.sharedExploreHashtags = []
        state.sharedExploreLocationSharing = nil
        state.exploreFieldNotesArePublic = false
        state.isExplorePostComposerPresented = false
        state.explorePostComposerPresentationScanId = nil
        state.explorePostComposerPresentationGeneration = nil
        state.explorePostComposerPresentationPostId = nil
        state.isCommunityRequestSheetPresented = false
        state.communityRequestPresentationScanId = nil
        state.communityRequestPresentationGeneration = nil
        state.communityRequestPresentationRequestId = nil
        state.showExploreOnboarding = false
        state.exploreOnboardingPresentationScanId = nil
        state.exploreOnboardingPresentationGeneration = nil
        state.showExploreSheet = false
        state.explorePresentationTarget = .automatic
        state.explorePresentationScanId = nil
        state.explorePresentationGeneration = nil
        state.toastMessage = nil
        toastAction = nil
    }

    func markRecordViewedIfAppropriate(modelContext: ModelContext) {
        guard inferenceEngine?.isProcessing == false,
              let engineScanId = inferenceEngine?.speciesData?.scanId,
              isPresentingLocalRecord(scanId: engineScanId),
              let record = fetchActiveLocalRecord(modelContext: modelContext),
              record.id.caseInsensitiveCompare(engineScanId) == .orderedSame,
              !record.hasBeenViewed else { return }

        record.hasBeenViewed = true
        activeLocalRecord = record
        _ = saveInsightMutation(
            modelContext,
            failureMessage: nil,
            logContext: "mark record viewed"
        )
    }
}
