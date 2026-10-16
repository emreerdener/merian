import Foundation
import SwiftData

/// Recovers exact durable operations. It never reconstructs consent from a scan projection.
@MainActor
struct ObservationPublicationDeliveryService {
    @MainActor struct Dependencies {
        var ownerID: () -> UUID? = { CloudDeletionAccountWork.currentAccountID }
        var begin: (UUID) throws -> AccountBoundWorkLease = { try SupabaseManager.shared.beginUnownedAccountBoundWork(expectedUserID: $0) }
        var finish: (AccountBoundWorkLease) -> Void = { SupabaseManager.shared.finishAccountBoundWork($0) }
        var current: (AccountBoundWorkLease) -> Bool = {
            !SupabaseManager.shared.isAuthTransitionInProgress && SupabaseManager.shared.isAccountBoundWorkLeaseCurrent($0)
        }
        var status: (ObservationPublicationStatusRequest, UUID) async throws -> ObservationPublicationReceipt = {
            try await MerianNetworkClient.shared.observationPublicationStatus($0, ownerID: $1)
        }
        var admit: (ObservationPublicationRequest, UUID) async throws -> ObservationPublicationReceipt = {
            try await MerianNetworkClient.shared.requestObservationPublication($0, ownerID: $1)
        }
        var now: () -> Date = Date.init
        var save: (ModelContext) throws -> Void = { try $0.save() }
    }
    var dependencies = Dependencies()

    func drain(container: ModelContainer, isAvailable: () -> Bool,
               didStart: () -> Void, requestRetry: () -> Void) async {
        guard isAvailable(), !Task.isCancelled, let owner = dependencies.ownerID(),
              let lease = try? dependencies.begin(owner) else { return }
        defer { dependencies.finish(lease) }
        func current() -> Bool {
            !Task.isCancelled && isAvailable() && dependencies.ownerID() == owner &&
                lease.session.userID == owner && dependencies.current(lease)
        }
        guard current() else { return }
        didStart()
        do {
            let candidates = try ObservationPublicationPersistence.candidates(container: container, ownerID: owner)
                .filter { $0.1 <= dependencies.now() }.prefix(16)
            for (intent, _) in candidates {
                guard current() else { return }
                let claim: ObservationPublicationPersistence.Claim
                do {
                    guard let claimed = try ObservationPublicationPersistence.claim(intent, at: dependencies.now(),
                        container: container, isCurrent: current, save: dependencies.save) else { continue }
                    claim = claimed
                } catch let error as ObservationPublicationPersistence.IntegrityError {
                    if case .accountChanged = error { return }
                    continue
                } catch { requestRetry(); return }
                var attemptedAdmission = false
                do {
                    try ObservationPublicationPersistence.requireDispatch(claim, at: dependencies.now(), container: container, isCurrent: current)
                    let receipt: ObservationPublicationReceipt
                    do {
                        receipt = try await dependencies.status(intent.identity, owner)
                    } catch {
                        guard current() else { return }
                        guard Self.isMissing(error), let request = intent.request else { throw error }
                        // Recheck deletion, ownership and exact claim after the status await,
                        // immediately before submitting the original immutable consent.
                        try ObservationPublicationPersistence.requireDispatch(claim, at: dependencies.now(), container: container, isCurrent: current)
                        attemptedAdmission = true
                        receipt = try await dependencies.admit(request, owner)
                    }
                    guard current() else { return }
                    _ = try ObservationPublicationPersistence.acknowledge(receipt, expected: intent, at: dependencies.now(),
                        container: container, isCurrent: current, claim: claim, save: dependencies.save)
                } catch {
                    guard current() else { return }
                    do {
                        try ObservationPublicationPersistence.retry(claim, at: dependencies.now(),
                            needsAttention: Self.requiresAttention(error, acknowledged: intent.request == nil || attemptedAdmission),
                            container: container, isCurrent: current, save: dependencies.save)
                    } catch is ObservationPublicationPersistence.IntegrityError {
                        // Deletion or a newer claim wins. Never upsert missing/replaced work.
                    } catch { requestRetry(); return }
                }
            }
        } catch { if current() { requestRetry() } }
    }

    static func isMissing(_ error: Error) -> Bool {
        guard case MerianError.httpError(statusCode: 404, message: _) = error else { return false }
        return EdgeFunctionErrorPolicy.stableCode(from: error) == "analysis_history_not_found"
    }

    private static func requiresAttention(_ error: Error, acknowledged: Bool) -> Bool {
        guard case let MerianError.httpError(statusCode: status, message: _) = error else { return false }
        guard let code = EdgeFunctionErrorPolicy.stableCode(from: error) else { return false }
        if acknowledged && isMissing(error) { return true }
        return (status == 400 && code == "invalid_analysis_history") ||
            (status == 409 && ["analysis_history_operation_conflict", "analysis_history_revision_conflict"].contains(code)) ||
            (status == 404 && code == "analysis_history_deleted")
    }
}
