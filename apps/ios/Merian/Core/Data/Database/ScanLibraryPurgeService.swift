import Foundation
import os
import SwiftData

/// Account erasure's local persistence and preference boundary. Repository
/// composition resets view projections before entering this synchronous owner.
@MainActor
enum ScanLibraryPurgeService {
    static func purge(
        modelContext: ModelContext,
        userDefaults: UserDefaults,
        resetRuntimeState: @MainActor () -> Void
    ) -> Bool {
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
            "✅ Successfully purged all SwiftData records and account-scoped preferences."
        )
        return true
    }
}
