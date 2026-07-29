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
            HapticManager.shared.triggerErrorThump()
            activeLocalRecord = nil
            activeLocalRecordId = nil
            toolbarRecordSnapshot = nil
            state.showBottomBarTools = false
            state.showDeleteConfirmation = false
            state.showNewCollectionAlert = false
            ScanRepository.shared.eradicateScan(record: record, modelContext: modelContext)
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
            HapticManager.shared.triggerErrorThump()
            return
        }

        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            state.toastMessage = actionMessage
        }
        activeLocalRecord = record
        toolbarRecordSnapshot = InsightToolbarRecordSnapshot(record: record)
        OfflineQueueManager.shared.enqueueCollectionSync()
        HapticManager.shared.triggerSelectionPulse()
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
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    state.toastMessage = failureMessage
                }
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

        inferenceEngine.load(from: record)
        bindPresentedRecord(record, modelContext: modelContext)
        return true
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
            cachedActiveMedia = context.capturedMediaSnapshot.activeScanMedia
            return
        }

        invalidateScanBoundPresentationState()
        queuedContext = context
        cachedActiveMedia = context.capturedMediaSnapshot.activeScanMedia
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
        scanBoundActionGeneration &+= 1
        sharedExploreStateRequestToken &+= 1
        sharedExploreStateRevision &+= 1
        invalidateFieldTripScanContributions()
        activeLocalRecord = nil
        activeLocalRecordId = nil
        toolbarRecordSnapshot = nil
        cachedActiveMedia = nil
        boundFieldNotesScanId = nil
        state.showBottomBarTools = false
        state.showDeleteConfirmation = false
        state.showSaveSuccessAlert = false
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
        toastActionTitle = nil
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
