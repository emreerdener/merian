import Foundation

@MainActor
extension InferenceReviewWorkflowCoordinator.Dependencies {
    static var live: Self {
        Self(syncPendingIdentificationReviews: {
            await OfflineQueueManager.shared.syncPendingIdentificationReviews()
        })
    }
}
