import Foundation
import SwiftData

extension OfflineQueueManager {
    func requestAnalysisReviewRecovery() {
        guard !TestExecutionCoordinator.isRunningTests, isOnline, !isCurrentNetworkConstrained,
              let context = modelContext, let owner = CloudDeletionAccountWork.currentAccountID else { return }
        let scheduler = OfflineJobScheduler.shared
        analysisReviewDeliveryOwner.start(operation: { [weak self] tokenCurrent in
            guard let self else { return }
            let current: @MainActor @Sendable () -> Bool = {
                tokenCurrent() && self.modelContext === context && self.isOnline && !self.isCurrentNetworkConstrained &&
                    CloudDeletionAccountWork.currentAccountID == owner
            }
            let cloud = ObservationHistoryCloudClient.live(manager: .shared)
            let service = ObservationAnalysisReviewDeliveryService.live(cloud: cloud, client: .shared)
            await ObservationAnalysisReviewDrain(cloud: cloud, deliver: service.deliver)
                .run(ownerID: owner, container: context.container, isCurrent: current,
                     didStart: { scheduler.analysisReviewDrainDidStart(using: self, ownerID: owner, container: context.container) },
                     requestRetry: { scheduler.scheduleAnalysisReviewRetry(using: self, ownerID: owner, container: context.container) })
        }, didFinish: { [weak self] in
            guard let self else { return }
            self.analysisReviewDeliveryDidFinish(ownerID: owner, context: context, currentOwnerID: CloudDeletionAccountWork.currentAccountID)
            scheduler.scheduleNextPersistedWake(using: self)
        })
    }
}
