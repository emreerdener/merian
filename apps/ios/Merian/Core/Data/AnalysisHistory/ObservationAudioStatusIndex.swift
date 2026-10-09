import Foundation
import SwiftData

/// Shared bounded local index only. It never interprets a record as source or execution authority.
@MainActor
struct ObservationAudioStatusIndex {
    enum Route: Equatable, Sendable { case legacy, source }
    struct Cursor: Equatable, Sendable {
        fileprivate let owner: UUID
        fileprivate let observation: UUID
        fileprivate let child: String
        fileprivate let route: Route
    }
    struct Links {
        let values: [(String, OfflineQueueWork)]
        let next: Cursor?
    }
    func page(ownerID: UUID, observationID: UUID, after cursor: Cursor?, limit: Int, route: Route,
              container: ModelContainer, isCurrent: () -> Bool) throws -> Links {
        guard (1...20).contains(limit), cursor.map({ $0.owner == ownerID && $0.observation == observationID && $0.route == route }) ?? true else {
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
        return Links(values: Array(links.prefix(limit)),
            next: links.count > limit ? .init(owner: ownerID, observation: observationID, child: links[limit - 1].0, route: route) : nil)
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

    func canOmit(_ error: any Error) -> Bool {
        switch error {
        case ObservationHistoryError.invalidSnapshot, ObservationHistoryError.unavailable, ObservationHistoryError.resultConflict,
             ObservationReanalysisPersistence.IntegrityError.conflict, ObservationReanalysisPersistence.IntegrityError.unavailable,
             MerianError.invalidResponse: return true
        default: return false
        }
    }
}
