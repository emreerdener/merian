import Foundation
import SwiftData

extension OfflineQueueManager {
    /// Explicit held video upload work only; no discovery, timer or automatic replay.
    @discardableResult
    func requestVideoEvidenceUpload(_ key: ObservationVideoUploadOwner.Key,
                                  proof: ObservationVideoPreparation.Verified,
                                  account: ObservationHistoryCloudClient, service: ObservationVideoUploadService,
                                  isCurrentAccount: @escaping @MainActor @Sendable (AuthTransitionSession, UInt64) -> Bool,
                                  didComplete: @escaping @MainActor () -> Void) -> ObservationVideoUploadOwner.Admission {
        guard isOnline, !isCurrentNetworkConstrained, let context = modelContext,
              ObjectIdentifier(context.container) == key.container,
              isCurrentAccount(key.session, key.generation) else { return .unavailable }
        let current: @MainActor @Sendable () -> Bool = { [weak self] in
            self?.modelContext === context && isCurrentAccount(key.session, key.generation)
        }
        return videoUploadOwner.start(key, account: account, isCurrent: current, permitsDispatch: { [weak self] in
            self?.isOnline == true && self?.isCurrentNetworkConstrained == false
        }, operation: { scope in
            _ = await service.run(key.snapshot, proof: proof, container: context.container, scope: scope)
        }, didFinish: {
            guard current() else { return }
            didComplete()
        })
    }
}
