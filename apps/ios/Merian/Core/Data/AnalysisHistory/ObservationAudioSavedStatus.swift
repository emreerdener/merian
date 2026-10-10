import Foundation
import SwiftData

/// Advisory local facts only. Reading never creates an execution capability or proves safe new admission.
@MainActor
struct ObservationAudioSavedStatus {
    enum Phase: Equatable, Sendable {
        case filesPending, admissionPending, boundIdle
        case runningUnconsumed, runningConsumed, heldUnconsumed, heldConsumed
    }
    struct Summary: Equatable, Sendable {
        let identity: OfflineQueueWork.Reanalysis
        let phase: Phase
    }
    typealias Cursor = ObservationAudioStatusIndex.Cursor
    struct Page: Sendable {
        let items: [Summary]
        let next: Cursor?
        /// Includes unsupported/photo/held drafts and invalid links; never interpret omissions as absence.
        let omittedCount: Int
    }
    typealias Read = @MainActor (OfflineQueueWork.Reanalysis, ModelContainer, @escaping @MainActor @Sendable () -> Bool) async throws -> ObservationAudioResumeStore.Saved
    var read: Read = { try await ObservationAudioResumeStore.read($0, container: $1, isCurrent: $2) }

    /// Caller supplies current common owner/generation/container scope; this local reader acquires no account lease.
    func page(ownerID: UUID, observationID: UUID, after cursor: Cursor? = nil, limit: Int = 20,
              container: ModelContainer, isCurrent: @escaping @MainActor @Sendable () -> Bool) async throws -> Page {
        let index = ObservationAudioStatusIndex()
        let links = try index.page(ownerID: ownerID, observationID: observationID, after: cursor,
            limit: limit, route: .legacy, container: container, isCurrent: isCurrent)
        var items: [Summary] = []
        for (_, work) in links.values {
            try Task.checkCancellation()
            guard isCurrent() else { throw ObservationHistoryError.accountChanged }
            guard case let .reanalysis(identity) = work, identity.ownerID == ownerID, identity.observationID == observationID else { continue }
            do {
                let saved = try await read(identity, container, isCurrent)
                try Task.checkCancellation()
                guard isCurrent() else { throw ObservationHistoryError.accountChanged }
                guard saved.proof.preparation.identity == identity else { throw ObservationHistoryError.resultConflict }
                items.append(.init(identity: identity, phase: try phase(saved.state)))
            } catch {
                // Only classified immutable validation failures are omissions. Store/I/O/account failures propagate.
                guard index.canOmit(error) else { throw error }
            }
        }
        try index.validateParentScope(ownerID: ownerID, observationID: observationID, container: container, isCurrent: isCurrent)
        return Page(items: items, next: links.next, omittedCount: links.values.count - items.count)
    }

    func validateParentScope(ownerID: UUID, observationID: UUID, container: ModelContainer, isCurrent: () -> Bool) throws {
        try ObservationAudioStatusIndex().validateParentScope(ownerID: ownerID, observationID: observationID,
            container: container, isCurrent: isCurrent)
    }

    private func phase(_ state: ObservationAudioResumeStore.State) throws -> Phase {
        switch state {
        case .preparation(.pending): return .filesPending
        case .preparation(.admissionPending): return .admissionPending
        case .preparation(.ready): throw ObservationHistoryError.unavailable
        case let .bound(snapshot):
            switch snapshot.work.state {
            case .idle: return .boundIdle
            case .running: return snapshot.work.consumedAttempt == nil ? .runningUnconsumed : .runningConsumed
            case .held: return snapshot.work.consumedAttempt == nil ? .heldUnconsumed : .heldConsumed
            }
        }
    }

}
