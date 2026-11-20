import Foundation
import SwiftData

extension OfflineQueueManager {
    /// One explicit initial reservation, followed only by known-success handoffs. No scheduler admission.
    @discardableResult
    func requestVideoSourceSubmission(_ key: ObservationVideoReservationOwner.Key,
                                      proof: ObservationVideoPreparation.Verified,
                                      account: ObservationHistoryCloudClient, submission: ObservationVideoSubmissionService,
                                      execution: ObservationVideoExecutionService, erasure: ObservationReanalysisErasureOwner,
                                      isCurrentAccount: @escaping @MainActor @Sendable (AuthTransitionSession, UInt64) -> Bool,
                                      didChange: @escaping @MainActor () -> Void) -> ObservationVideoReservationOwner.Admission {
        guard isOnline, !isCurrentNetworkConstrained, let context = modelContext,
              ObjectIdentifier(context.container) == key.container,
              isCurrentAccount(key.session, key.generation) else { return .unavailable }
        let current: @MainActor @Sendable () -> Bool = { [weak self] in
            self?.modelContext === context && isCurrentAccount(key.session, key.generation)
        }
        var uploaded: ObservationVideoUploadLifecycleStore.Snapshot?
        return videoReservationOwner.start(key, account: account, isCurrent: current, permitsDispatch: { [weak self] in
            self?.isOnline == true && self?.isCurrentNetworkConstrained == false
        }, operation: { scope in
            uploaded = await submission.reserve(key.snapshot, proof: proof, container: context.container, scope: scope)
        }, didFinish: { [weak self] in
            guard current() else { return }
            // The prior account lease and slot have exited before the next owner admits work.
            if let uploaded, !Task.isCancelled {
                self?.requestVideoUploadSubmission(.init(snapshot: uploaded, session: key.session,
                    generation: key.generation, container: key.container), proof: proof, account: account,
                    submission: submission, execution: execution, erasure: erasure,
                    isCurrentAccount: isCurrentAccount, didChange: didChange)
            }
            didChange()
        })
    }

    /// Explicit upload/binding continuation. Unknown upload attempts remain held by their durable owner.
    @discardableResult
    func requestVideoUploadSubmission(_ key: ObservationVideoUploadOwner.Key,
                                      proof: ObservationVideoPreparation.Verified,
                                      account: ObservationHistoryCloudClient, submission: ObservationVideoSubmissionService,
                                      execution: ObservationVideoExecutionService, erasure: ObservationReanalysisErasureOwner,
                                      isCurrentAccount: @escaping @MainActor @Sendable (AuthTransitionSession, UInt64) -> Bool,
                                      didChange: @escaping @MainActor () -> Void) -> ObservationVideoUploadOwner.Admission {
        guard isOnline, !isCurrentNetworkConstrained, let context = modelContext,
              ObjectIdentifier(context.container) == key.container,
              isCurrentAccount(key.session, key.generation) else { return .unavailable }
        let current: @MainActor @Sendable () -> Bool = { [weak self] in
            self?.modelContext === context && isCurrentAccount(key.session, key.generation)
        }
        var bound: ObservationVideoExecutionStore.Snapshot?
        return videoUploadOwner.start(key, account: account, isCurrent: current, permitsDispatch: { [weak self] in
            self?.isOnline == true && self?.isCurrentNetworkConstrained == false
        }, operation: { scope in
            bound = await submission.deliver(key.snapshot, proof: proof, container: context.container, scope: scope)
        }, didFinish: { [weak self] in
            guard current() else { return }
            if let bound, !Task.isCancelled {
                self?.requestVideoExecution(.init(snapshot: bound, session: key.session,
                    generation: key.generation, container: key.container), proof: proof, account: account,
                    service: execution, erasure: erasure, isCurrentAccount: isCurrentAccount, didComplete: didChange)
            }
            didChange()
        })
    }
}
