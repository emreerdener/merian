import Foundation
import SwiftData

/// Bounded owner-private status projection. Reading never admits, retries or repairs work.
@MainActor
struct ObservationReanalysisOperationStatus {
    enum Phase: Equatable, Sendable {
        case preparingEvidence, waitingToStart, processing, waitingToRetry
        case consentRequired, evidenceUnavailable, reconciliationRequired, retryLimit, terminalFailure
    }
    struct Summary: Identifiable, Equatable, Sendable {
        let id: UUID
        let sourceAnalysisID: UUID
        let phase: Phase
    }
    struct Cursor: Equatable, Sendable { fileprivate let childID: String }
    struct Page: Sendable {
        let items: [Summary]
        let next: Cursor?
    }
    var account = ObservationHistoryCloudClient.live

    func page(observationID: UUID, ownerID: UUID, after cursor: Cursor? = nil, limit: Int = 20,
              container: ModelContainer, isCurrent: @escaping () -> Bool) throws -> Page {
        guard (1...20).contains(limit) else { throw ObservationHistoryError.invalidPage }
        let lease = try account.begin(ownerID)
        defer { account.finish(lease) }
        let valid = { isCurrent() && lease.session.userID == ownerID && account.isCurrent(lease) }
        let parent = observationID.uuidString.lowercased(), owner = ownerID.uuidString.lowercased()
        let links: [(String, OfflineQueueWork)] = try ConfirmedSpeciesReviewPersistence.transaction {
            try validateParent(parent, owner: owner, container: container, isCurrent: valid)
            let context = ModelContext(container), after = cursor?.childID ?? "", kind = "reanalysis"
            var query = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate {
                $0.workKindRaw == kind && $0.parentObservationID == parent && $0.reanalysisOwnerAccountID == owner && $0.id > after
            }, sortBy: [SortDescriptor(\.id)])
            query.fetchLimit = limit + 1
            query.propertiesToFetch = [\.id, \.workKindRaw, \.parentObservationID, \.sourceAnalysisID, \.reanalysisOwnerAccountID]
            return try context.fetch(query).map { ($0.id, $0.work) }
        }
        var items: [Summary] = []
        for (_, work) in links.prefix(limit) {
            try Task.checkCancellation()
            guard valid() else { throw ObservationHistoryError.accountChanged }
            guard case let .reanalysis(identity) = work, identity.ownerID == ownerID, identity.observationID == observationID else { continue }
            if let phase = try phase(identity, container: container, isCurrent: valid) {
                items.append(.init(id: identity.analysisID, sourceAnalysisID: identity.sourceAnalysisID, phase: phase))
            }
        }
        try ConfirmedSpeciesReviewPersistence.transaction {
            try validateParent(parent, owner: owner, container: container, isCurrent: valid)
        }
        // Advance over every inspected linkage, even omitted corruption. Never imply chronology.
        return Page(items: items, next: links.count > limit ? Cursor(childID: links[limit - 1].0) : nil)
    }

    /// Caller owns the read transaction; no nested persistence lock or persistent mutation.
    private func validateParent(_ parent: String, owner: String, container: ModelContainer, isCurrent: () -> Bool) throws {
        try Task.checkCancellation()
        guard isCurrent() else { throw ObservationHistoryError.accountChanged }
        let context = ModelContext(container)
        let scan = try ObservationHistorySyncService.enrolledScan(parent, context: context)
        guard scan.analysisOwnerAccountID == owner,
              !(try ObservationHistoryEnrollmentIntent.holds(parent, context: context)) else { throw ObservationHistoryError.unavailable }
    }

    private func phase(_ identity: OfflineQueueWork.Reanalysis, container: ModelContainer, isCurrent: () -> Bool) throws -> Phase? {
        // Completed results belong to history. A receipt alone can mean discard,
        // so neither receipts nor any result/transport collision imply completion here.
        let exists = try ConfirmedSpeciesReviewPersistence.transaction {
            let context = ModelContext(container), lower = identity.analysisID.uuidString.lowercased(), upper = identity.analysisID.uuidString
            var query = FetchDescriptor<LocalAnalysisRecord>(predicate: #Predicate { $0.id == lower || $0.id == upper })
            query.fetchLimit = 1; query.propertiesToFetch = [\.id]
            return try !context.fetch(query).isEmpty
        }
        guard !exists else { return nil }
        if let saved = try? ObservationReanalysisAdmissionStore.read(identity, container: container, isCurrent: isCurrent) {
            if let hold = saved.work.hold {
                switch hold {
                case .consentRequired: return .consentRequired
                case .evidenceUnavailable: return .evidenceUnavailable
                case .reconciliationRequired: return .reconciliationRequired
                case .retryLimit: return .retryLimit
                }
            }
            if saved.work.state == .waiting { return .waitingToRetry }
            return saved.work.phase == .filesPending ? .preparingEvidence : .waitingToStart
        }
        guard isCurrent() else { throw ObservationHistoryError.accountChanged }
        guard let saved = try? ObservationReanalysisExecutionStore.read(identity, container: container, isCurrent: isCurrent) else { return nil }
        switch saved.status {
        case .pending: return .waitingToStart
        case .running: return .processing
        case .waiting: return .waitingToRetry
        case .needsAttention:
            switch saved.hold {
            case .consentRequired: return .consentRequired
            case .evidenceUnavailable: return .evidenceUnavailable
            case .terminalFailure: return .terminalFailure
            case .reconciliationRequired: return .reconciliationRequired
            case .retryLimit: return .retryLimit
            case nil: return nil // Held legacy drafts have never been explicitly admitted.
            }
        default: return nil
        }
    }
}
