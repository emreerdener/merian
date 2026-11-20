import Foundation
import SwiftData

extension OfflineQueueManager {
    /// Explicit staged source work only. Both owners retain their own account lease until actual exit.
    @discardableResult
    func requestAudioSourceSubmission(_ key: ObservationSourceReservationOwner.Key,
                                      proof: ObservationAudioPreparation.Verified,
                                      account: ObservationHistoryCloudClient, source: ObservationAudioSourceSubmissionService,
                                      execution: ObservationAudioExecutionService, erasure: ObservationReanalysisErasureOwner,
                                      isCurrentAccount: @escaping @MainActor @Sendable (AuthTransitionSession, UInt64) -> Bool,
                                      didChange: @escaping @MainActor () -> Void) -> ObservationSourceReservationOwner.Admission {
        guard isOnline, !isCurrentNetworkConstrained, let context = modelContext,
              ObjectIdentifier(context.container) == key.container,
              ObservationAudioSourceSubmissionService.admission(for: key.snapshot) == key.admission,
              isCurrentAccount(key.session, key.generation) else { return .unavailable }
        let current: @MainActor @Sendable () -> Bool = { [weak self] in
            self?.modelContext === context && isCurrentAccount(key.session, key.generation)
        }
        var bound: ObservationAudioExecutionStore.Snapshot?
        return sourceReservationOwner.start(key, account: account, isCurrent: current, permitsDispatch: { [weak self] in
            self?.isOnline == true && self?.isCurrentNetworkConstrained == false
        }, operation: { scope in
            bound = await source.run(key.snapshot, admission: key.admission, proof: proof, container: context.container, scope: scope)
        }, didFinish: { [weak self] in
            guard current() else { return }
            // The source owner has released its lease and slot. Only a normal return may advance.
            // The execution owner rechecks cancellation, Auth admission, network and container.
            if let bound, !Task.isCancelled {
                let next = ObservationAudioExecutionOwner.Key(snapshot: bound, session: key.session,
                    generation: key.generation, container: key.container)
                self?.requestAudioExecution(next, proof: proof, account: account, service: execution,
                    erasure: erasure, isCurrentAccount: isCurrentAccount, didComplete: didChange)
            }
            didChange()
        })
    }
}
