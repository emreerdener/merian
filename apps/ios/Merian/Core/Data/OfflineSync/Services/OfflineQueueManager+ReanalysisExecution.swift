import Foundation
import SwiftData

extension OfflineQueueManager {
    /// Restores only durably admitted bound children. Draft binding remains an explicit submission action.
    func requestReanalysisExecutionRecovery() {
        guard !TestExecutionCoordinator.isRunningTests, isOnline, !isCurrentNetworkConstrained,
              let context = modelContext, let owner = CloudDeletionAccountWork.currentAccountID else { return }
        let scheduler = OfflineJobScheduler.shared
        let manager = SupabaseManager.shared, generation = manager.authSessionGeneration
        reanalysisExecutionOwner.start(operation: { [weak self] scope in
            guard let self else { return }
            let settlementCurrent: @MainActor @Sendable () -> Bool = {
                scope.maySettleKnownReceipt() && manager.authSessionGeneration == generation && self.modelContext === context &&
                    CloudDeletionAccountWork.currentAccountID == owner && !manager.isAuthTransitionInProgress
            }
            let current: @MainActor @Sendable () -> Bool = {
                scope.mayDispatch() && manager.authSessionGeneration == generation && self.modelContext === context && self.isOnline && !self.isCurrentNetworkConstrained &&
                    CloudDeletionAccountWork.currentAccountID == owner && !manager.isAuthTransitionInProgress
            }
            await ObservationReanalysisExecutionService(account: .live(manager: manager),
                retirement: .init(dependencies: .live(client: .shared))).drain(ownerID: owner, container: context.container,
                isCurrent: current, maySettleKnownReceipt: settlementCurrent, didStart: { scheduler.reanalysisDrainDidStart(using: self) },
                requestRetry: { scheduler.scheduleReanalysisRetry(using: self) },
                cleanup: { await self.drainPendingReanalysisErasures(in: context.container) },
                didComplete: { AppDIContainer.shared.appEventPublisher.send(.scanLibraryChanged) })
        }, didFinish: { [weak self] in
            guard let self else { return }
            if manager.authSessionGeneration == generation, !manager.isAuthTransitionInProgress {
                self.reanalysisExecutionDidFinish(ownerID: owner, context: context, currentOwnerID: CloudDeletionAccountWork.currentAccountID)
            }
            scheduler.scheduleNextPersistedWake(using: self)
        })
    }

    func awaitRetainedSyncQuiescenceForAuthTransition() async {
        protectedChatRefreshOwner.cancelAll()
        protectedChatDeliveryOwner.invalidate()
        sourceReservationOwner.invalidate()
        audioExecutionOwner.invalidate()
        audioStatusOwner.invalidate()
        confirmationUndoOwner.cancelAll()
        rejectionUndoOwner.cancelAll()
        analysisReviewDeliveryOwner.cancel()
        reanalysisExecutionOwner.invalidate()
        reanalysisAdmissionRuntime.cancel()
        reanalysisPreparationOwner.cancelAll()
        historyEnrollmentOwner.cancelAll()
        publicationConsentPreparationOwner.cancelAll()
        publicationTargetRecoveryOwner.cancelAll()
        await protectedChatRefreshOwner.cancelAndAwaitAll()
        await publicationTargetRecoveryOwner.cancelAndAwaitAll()
        await publicationConsentPreparationOwner.cancelAndAwaitAll()
        await historyEnrollmentOwner.cancelAndAwaitAll()
        await reanalysisPreparationOwner.cancelAndAwaitAll()
        await reanalysisAdmissionRuntime.cancelAndAwait()
        await awaitCollectionSyncQuiescenceForAuthTransition()
        await reanalysisExecutionOwner.cancelAndAwait()
        await confirmationUndoOwner.cancelAndAwaitAll()
        await rejectionUndoOwner.cancelAndAwaitAll()
        await analysisReviewDeliveryOwner.cancelAndAwait()
        await protectedChatDeliveryOwner.invalidateAndAwait()
        await sourceReservationOwner.invalidateAndAwait()
        await audioExecutionOwner.invalidateAndAwait()
        await audioStatusOwner.invalidateAndAwait()
    }
}
