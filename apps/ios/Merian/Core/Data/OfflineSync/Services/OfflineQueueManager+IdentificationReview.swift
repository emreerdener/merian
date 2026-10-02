import Foundation
import SwiftData

extension OfflineQueueManager {
    func syncPendingIdentificationReviews() async {
        guard isOnline, let context = modelContext else { return }
        if let task = identificationReviewSyncTask { await task.value; return }
        let generation = UUID()
        identificationReviewSyncGeneration = generation
        let task = Task { @MainActor in
            await IdentificationReviewSyncService().drain(context: context)
        }
        identificationReviewSyncTask = task
        await task.value
        guard identificationReviewSyncGeneration == generation else { return }
        identificationReviewSyncTask = nil
        identificationReviewSyncGeneration = nil
        OfflineJobScheduler.shared.scheduleNextPersistedWake(using: self)
    }
}
