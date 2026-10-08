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
    struct Cursor: Equatable, Sendable {
        fileprivate let owner: UUID
        fileprivate let observation: UUID
        fileprivate let child: String
    }
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
        guard (1...20).contains(limit), cursor.map({ $0.owner == ownerID && $0.observation == observationID }) ?? true else {
            throw ObservationHistoryError.invalidPage
        }
        let owner = ownerID.uuidString.lowercased(), parent = observationID.uuidString.lowercased()
        let links: [(String, OfflineQueueWork)] = try ConfirmedSpeciesReviewPersistence.transaction {
            try validate(owner: owner, parent: parent, container: container, isCurrent: isCurrent)
            let context = ModelContext(container), after = cursor?.child ?? "", kind = "reanalysis"
            var query = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate {
                $0.workKindRaw == kind && $0.parentObservationID == parent && $0.reanalysisOwnerAccountID == owner && $0.id > after
            }, sortBy: [SortDescriptor(\.id, comparator: .lexical)])
            query.fetchLimit = limit + 1
            query.propertiesToFetch = [\.id, \.workKindRaw, \.parentObservationID, \.sourceAnalysisID, \.reanalysisOwnerAccountID]
            return try context.fetch(query).map { ($0.id, $0.work) }
        }
        var items: [Summary] = []
        for (_, work) in links.prefix(limit) {
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
                guard canOmit(error) else { throw error }
            }
        }
        try ConfirmedSpeciesReviewPersistence.transaction {
            try validate(owner: owner, parent: parent, container: container, isCurrent: isCurrent)
        }
        return Page(items: items, next: links.count > limit ? .init(owner: ownerID, observation: observationID, child: links[limit - 1].0) : nil,
            omittedCount: min(limit, links.count) - items.count)
    }

    /// Opening fence only: no enumeration, lease, file read or admission authority.
    func validateParentScope(ownerID: UUID, observationID: UUID, container: ModelContainer, isCurrent: () -> Bool) throws {
        try ConfirmedSpeciesReviewPersistence.transaction {
            try validate(owner: ownerID.uuidString.lowercased(), parent: observationID.uuidString.lowercased(),
                container: container, isCurrent: isCurrent)
        }
    }

    /// Caller holds the shared lock; never nest it.
    private func validate(owner: String, parent: String, container: ModelContainer, isCurrent: () -> Bool) throws {
        try Task.checkCancellation()
        guard isCurrent() else { throw ObservationHistoryError.accountChanged }
        let context = ModelContext(container), scan = try ObservationHistorySyncService.enrolledScan(parent, context: context)
        guard scan.analysisOwnerAccountID == owner, !(try ObservationHistoryEnrollmentIntent.holds(parent, context: context)) else {
            throw ObservationHistoryError.unavailable
        }
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

    private func canOmit(_ error: any Error) -> Bool {
        switch error {
        case ObservationHistoryError.invalidSnapshot, ObservationHistoryError.unavailable, ObservationHistoryError.resultConflict,
             ObservationReanalysisPersistence.IntegrityError.conflict, ObservationReanalysisPersistence.IntegrityError.unavailable,
             MerianError.invalidResponse: return true
        default: return false
        }
    }
}
