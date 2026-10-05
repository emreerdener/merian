import Foundation
import SwiftData

extension OfflineQueueManager {
    /// Restores only durably admitted bound children. Draft binding remains an explicit submission action.
    func requestReanalysisExecutionRecovery() {
        guard !TestExecutionCoordinator.isRunningTests, isOnline, !isCurrentNetworkConstrained,
              let context = modelContext, let owner = CloudDeletionAccountWork.currentAccountID else { return }
        let scheduler = OfflineJobScheduler.shared
        reanalysisExecutionOwner.start(operation: { [weak self] tokenCurrent in
            guard let self else { return }
            let current: @MainActor @Sendable () -> Bool = {
                tokenCurrent() && self.modelContext === context && self.isOnline && !self.isCurrentNetworkConstrained &&
                    CloudDeletionAccountWork.currentAccountID == owner
            }
            await ObservationReanalysisExecutionService().drain(ownerID: owner, container: context.container,
                isCurrent: current, didStart: { scheduler.reanalysisDrainDidStart(using: self) },
                requestRetry: { scheduler.scheduleReanalysisRetry(using: self) },
                cleanup: { await self.drainPendingReanalysisErasures(in: context.container) })
        }, didFinish: { [weak self] in
            guard let self else { return }
            scheduler.scheduleNextPersistedWake(using: self)
        })
    }

    func awaitRetainedSyncQuiescenceForAuthTransition() async {
        reanalysisExecutionOwner.cancel()
        reanalysisAdmissionRuntime.cancel()
        reanalysisPreparationOwner.cancelAll()
        historyEnrollmentOwner.cancelAll()
        await historyEnrollmentOwner.cancelAndAwaitAll()
        await reanalysisPreparationOwner.cancelAndAwaitAll()
        await reanalysisAdmissionRuntime.cancelAndAwait()
        await awaitCollectionSyncQuiescenceForAuthTransition()
        await reanalysisExecutionOwner.cancelAndAwait()
    }
}
