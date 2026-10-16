import Foundation
import SwiftData

extension OfflineQueueManager {
    /// Explicit action only. No candidate discovery, scheduler wake or automatic replay.
    @discardableResult
    func requestAudioExecution(_ key: ObservationAudioExecutionOwner.Key,
                               proof: ObservationAudioPreparation.Verified,
                               account: ObservationHistoryCloudClient, service: ObservationAudioExecutionService,
                               erasure: ObservationReanalysisErasureOwner,
                               isCurrentAccount: @escaping @MainActor @Sendable (AuthTransitionSession, UInt64) -> Bool,
                               didComplete: @escaping @MainActor () -> Void) -> ObservationAudioExecutionOwner.Admission {
        guard isOnline, !isCurrentNetworkConstrained, let context = modelContext,
              ObjectIdentifier(context.container) == key.container,
              isCurrentAccount(key.session, key.generation) else { return .unavailable }
        let current: @MainActor @Sendable () -> Bool = { [weak self] in
            self?.modelContext === context && isCurrentAccount(key.session, key.generation)
        }
        return audioExecutionOwner.start(key, account: account, isCurrent: current, permitsDispatch: { [weak self] in
            self?.isOnline == true && self?.isCurrentNetworkConstrained == false
        }, operation: { scope in
            _ = await service.run(key.snapshot, proof: proof, container: context.container, scope: scope, cleanup: { receipt in
                guard scope.maySettleKnownReceipt() else { return }
                await erasure.erase(receipt, container: context.container, isCurrent: scope.maySettleKnownReceipt)
                guard scope.maySettleKnownReceipt() else { return }
                didComplete()
            })
        }, didFinish: {})
    }
}
