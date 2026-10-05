import Foundation
import os
import SwiftData

/// Account erasure's local persistence and preference boundary. Repository
/// composition resets view projections before entering this asynchronous owner.
@MainActor
enum ScanLibraryPurgeService {
    static func purge(
        modelContext: ModelContext,
        userDefaults: UserDefaults,
        resetRuntimeState: @MainActor () -> Void,
        eraseReanalysis: @MainActor () async throws -> Void = {
            try await ObservationReanalysisFileStore(documents: .documentsDirectory).purgeNamespace()
        }
    ) async -> Bool {
        let cleanup = OfflineQueueManager.shared.reanalysisErasureOwner
        await cleanup.suspendForLibraryPurge()
        defer { cleanup.resumeAfterLibraryPurge() }
        LocalScanMediaRecoveryResolver.resetRegisteredRecoveryMappings()
        do {
            try modelContext.delete(model: CapturedMediaEntry.self)
            try modelContext.delete(model: LocalAnalysisStateRecord.self)
            try modelContext.delete(model: LocalAnalysisRecord.self)
            try modelContext.delete(model: LocalScanRecord.self)
            try modelContext.delete(model: ScanCollection.self)
            try modelContext.delete(model: OfflineQueuedScan.self)
            try modelContext.delete(model: ActiveOfflineQueuedScanGoalHint.self)
            try modelContext.delete(model: PendingCloudDeletionTask.self)
            try modelContext.delete(model: UserSpeciesPreference.self)
            try modelContext.delete(model: OfflineJobRecord.self)
            try modelContext.delete(model: OfflineQueueEvent.self)
            try modelContext.save()
        } catch {
            modelContext.rollback()
            AppDIContainer.shared.appEventPublisher.send(.scanLibraryChanged)
            MerianLog.data.error("🚨 Failed to erase local ModelContainer: \(error.localizedDescription, privacy: .private)")
            return false
        }

        do {
            // Auth transition/recovery barriers remain held across this suspension.
            // Failure after the row commit keeps the durable cleanup marker for an idempotent retry.
            try await eraseReanalysis()
        } catch {
            AppDIContainer.shared.appEventPublisher.send(.scanLibraryChanged)
            MerianLog.data.error("Private reanalysis erasure remains pending; retaining account cleanup barrier.")
            return false
        }

        guard AccountScopedPreferences.purgeAndVerify(
            userDefaults: userDefaults
        ) else {
            AppDIContainer.shared.appEventPublisher.send(.scanLibraryChanged)
            MerianLog.data.error(
                "Failed to verify account-scoped preference cleanup."
            )
            return false
        }

        resetRuntimeState()
        AppDIContainer.shared.appEventPublisher.send(.scanLibraryChanged)
        MerianLog.data.debug(
            "✅ Successfully purged SwiftData, private reanalysis files and account-scoped preferences."
        )
        return true
    }
}
