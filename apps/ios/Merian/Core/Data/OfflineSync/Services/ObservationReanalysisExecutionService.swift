import Foundation
import SwiftData

/// One bounded pass over explicitly admitted work. The retained owner supplies cancellation/generation authority.
@MainActor
struct ObservationReanalysisExecutionService {
    typealias Store = ObservationReanalysisExecutionStore
    var account = ObservationHistoryCloudClient.live
    var candidates: (UUID, ModelContainer, @escaping @MainActor @Sendable () -> Bool) throws -> [Store.Candidate] = {
        try Store.candidates(ownerID: $0, container: $1, isCurrent: $2)
    }
    var execute: (Store.Candidate, ModelContainer, @escaping @MainActor @Sendable () -> Bool) async throws -> ObservationReanalysisExecutor.Outcome = {
        let worker = ObservationReanalysisExecutor(dependencies: .live(
            files: ObservationReanalysisFileStore(documents: .documentsDirectory), client: .shared))
        return try await worker.execute($0.snapshot, admission: $0.admission, container: $1, isCurrent: $2)
    }
    var now: () -> Date = Date.init

    func drain(ownerID: UUID, container: ModelContainer,
               isCurrent: @escaping @MainActor @Sendable () -> Bool,
               didStart: () -> Void, requestRetry: () -> Void,
               cleanup: () async -> Void, didComplete: () -> Void = {}) async {
        guard isCurrent(), !Task.isCancelled else { return }
        let lease: AccountBoundWorkLease
        do { lease = try account.begin(ownerID) } catch {
            if isCurrent(), !Task.isCancelled { requestRetry() }
            return
        }
        defer { account.finish(lease) }
        let current: @MainActor @Sendable () -> Bool = {
            lease.session.userID == ownerID && account.isCurrent(lease) && isCurrent()
        }
        guard current(), !Task.isCancelled else { return }
        didStart()
        do {
            let due = try candidates(ownerID, container, current).filter { $0.due <= now() }.prefix(8)
            for candidate in due {
                guard current(), !Task.isCancelled else { return }
                let outcome = try await execute(candidate, container, current)
                guard current(), !Task.isCancelled else { return }
                if case .completed = outcome {
                    // Notify only after the executor's atomic append, before optional file cleanup.
                    didComplete()
                    await cleanup()
                }
            }
        } catch {
            guard current(), !Task.isCancelled else { return }
            requestRetry()
        }
    }
}
