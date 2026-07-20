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

    func eradicateCurrentScan(modelContext: ModelContext, inferenceEngine: InferenceEngine, dismiss: DismissAction) {
        guard let targetId = inferenceEngine.speciesData?.scanId else { return }

        if let record = fetchLocalRecord(scanId: targetId, modelContext: modelContext) {
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

    func toggleScanInCollection(_ collection: ScanCollection, modelContext: ModelContext) {
        guard let record = fetchActiveLocalRecord(modelContext: modelContext) else { return }

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

    func fetchLocalRecord(for scanId: String, modelContext: ModelContext) {
        if let record = fetchLocalRecord(scanId: scanId, modelContext: modelContext) {
            bindPresentedRecord(record, modelContext: modelContext)
        }
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
            activeLocalRecord = nil
            activeLocalRecordId = nil
            toolbarRecordSnapshot = nil
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
        var descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.id == scanId }
        )
        descriptor.fetchLimit = 1

        guard let record = (try? modelContext.fetch(descriptor))?.first else {
            return false
        }

        inferenceEngine.load(from: record)
        bindPresentedRecord(record, modelContext: modelContext)
        queuedContext = nil

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
        activeLocalRecord = record
        activeLocalRecordId = record.id
        toolbarRecordSnapshot = InsightToolbarRecordSnapshot(record: record)
        cachedActiveMedia = record.capturedMediaSnapshot.activeScanMedia
        refreshSharedExploreStateFromLocalCache(scanId: record.id)
        syncFieldNotesFromCurrentScan(modelContext: modelContext)
        markRecordViewedIfAppropriate(modelContext: modelContext)
    }
    func markRecordViewedIfAppropriate(modelContext: ModelContext) {
        guard inferenceEngine?.isProcessing == false,
              let record = fetchActiveLocalRecord(modelContext: modelContext),
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
