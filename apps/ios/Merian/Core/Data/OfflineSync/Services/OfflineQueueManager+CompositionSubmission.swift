import Foundation
import SwiftData

extension OfflineQueueManager {
    /// One explicit initial reservation, followed only by known-success handoffs. No scheduler admission.
    @discardableResult
    func requestCompositionSourceSubmission(_ key: ObservationCompositionReservationOwner.Key,
                                            proof: ObservationCompositionPreparation.Verified,
                                            account: ObservationHistoryCloudClient, submission: ObservationCompositionSubmissionService,
                                            execution: ObservationCompositionExecutionService, erasure: ObservationReanalysisErasureOwner,
                                            isCurrentAccount: @escaping @MainActor @Sendable (AuthTransitionSession, UInt64) -> Bool,
                                            didChange: @escaping @MainActor () -> Void) -> ObservationCompositionReservationOwner.Admission {
        guard isOnline, !isCurrentNetworkConstrained, let context = modelContext,
              ObjectIdentifier(context.container) == key.container,
              isCurrentAccount(key.session, key.generation) else { return .unavailable }
        let current: @MainActor @Sendable () -> Bool = { [weak self] in
            self?.modelContext === context && isCurrentAccount(key.session, key.generation)
        }
        var uploaded: CompositionUploadLifecycleStore.Snapshot?
        return compositionReservationOwner.start(key, account: account, isCurrent: current, permitsDispatch: { [weak self] in
            self?.isOnline == true && self?.isCurrentNetworkConstrained == false
        }, operation: { scope in
            uploaded = await submission.reserve(key.snapshot, proof: proof, container: context.container, scope: scope)
        }, didFinish: { [weak self] in
            guard current() else { return }
            // The prior account lease and slot have exited before the next owner admits work.
            if let uploaded, !Task.isCancelled {
                self?.requestCompositionUploadSubmission(.init(snapshot: uploaded, session: key.session,
                    generation: key.generation, container: key.container), proof: proof, account: account,
                    submission: submission, execution: execution, erasure: erasure,
                    isCurrentAccount: isCurrentAccount, didChange: didChange)
            }
            didChange()
        })
    }

    /// Explicit upload/binding continuation. Unknown upload attempts remain held by their durable owner.
    @discardableResult
    func requestCompositionUploadSubmission(_ key: ObservationCompositionUploadOwner.Key,
                                            proof: ObservationCompositionPreparation.Verified,
                                            account: ObservationHistoryCloudClient, submission: ObservationCompositionSubmissionService,
                                            execution: ObservationCompositionExecutionService, erasure: ObservationReanalysisErasureOwner,
                                            isCurrentAccount: @escaping @MainActor @Sendable (AuthTransitionSession, UInt64) -> Bool,
                                            didChange: @escaping @MainActor () -> Void) -> ObservationCompositionUploadOwner.Admission {
        guard isOnline, !isCurrentNetworkConstrained, let context = modelContext,
              ObjectIdentifier(context.container) == key.container,
              isCurrentAccount(key.session, key.generation) else { return .unavailable }
        let current: @MainActor @Sendable () -> Bool = { [weak self] in
            self?.modelContext === context && isCurrentAccount(key.session, key.generation)
        }
        var bound: ObservationCompositionExecutionStore.Snapshot?
        return compositionUploadOwner.start(key, account: account, isCurrent: current, permitsDispatch: { [weak self] in
            self?.isOnline == true && self?.isCurrentNetworkConstrained == false
        }, operation: { scope in
            bound = await submission.deliver(key.snapshot, proof: proof, container: context.container, scope: scope)
        }, didFinish: { [weak self] in
            guard current() else { return }
            if let bound, !Task.isCancelled {
                self?.requestCompositionExecution(.init(snapshot: bound, session: key.session,
                    generation: key.generation, container: key.container), proof: proof, account: account,
                    service: execution, erasure: erasure, isCurrentAccount: isCurrentAccount, didComplete: didChange)
            }
            didChange()
        })
    }
}
