import Foundation
import SwiftData

/// Explicit foreground consent. Delivery starts only from a durably saved operation.
@MainActor
struct ObservationPublicationConsentService {
    struct Prepared {
        var ownerID: UUID { ticket.ownerID }
        fileprivate let ticket: ObservationAnalysisReviewTicket
        let snapshot: ObservationPublicationConsentSnapshot
        fileprivate init(ticket: ObservationAnalysisReviewTicket, snapshot: ObservationPublicationConsentSnapshot) {
            self.ticket = ticket; self.snapshot = snapshot
        }

        /// Call only on final user acceptance; retain this value across save retries.
        /// This initial flow explicitly shares photos without a public note.
        func accepting(mediaIDs: [UUID], makeOperationID: () -> UUID = UUID.init) throws -> Acceptance {
            guard (1...6).contains(mediaIDs.count), Set(mediaIDs).count == mediaIDs.count,
                  Set(mediaIDs).isSubset(of: Set(snapshot.media.map(\.mediaID))) else {
                throw MerianError.invalidResponse
            }
            return try Acceptance(prepared: self, request: ObservationPublicationRequest(
                operationID: makeOperationID(), observationID: snapshot.observationID, analysisID: snapshot.analysisID,
                expectedObservationRevision: snapshot.expectedObservationRevision,
                expectedReviewRevision: snapshot.expectedReviewRevision, taxonomyVersionID: snapshot.taxonomyVersionID,
                initialTaxonID: nil, note: nil, mediaIDs: mediaIDs))
        }
    }

    struct Acceptance {
        let request: ObservationPublicationRequest
        fileprivate let prepared: Prepared
        fileprivate init(prepared: Prepared, request: ObservationPublicationRequest) {
            self.prepared = prepared; self.request = request
        }
    }

    var cloud = ObservationHistoryCloudClient.live
    var fetch: (ObservationPublicationConsentRequest, UUID) async throws -> ObservationPublicationConsentSnapshot = {
        try await MerianNetworkClient.shared.prepareObservationPublicationConsent($0, ownerID: $1)
    }
    var save: (ModelContext) throws -> Void = { try $0.save() }
    var wake: () -> Void = {
        OfflineJobScheduler.shared.scheduleNextPersistedWake(using: OfflineQueueManager.shared)
    }

    func prepare(ticket: ObservationAnalysisReviewTicket, container: ModelContainer,
                 isCurrent: () -> Bool) async throws -> Prepared {
        let observationID = ticket.observationID, analysisID = ticket.analysisID, ownerID = ticket.ownerID
        func current() -> Bool { !Task.isCancelled && isCurrent() }
        guard current() else { throw ObservationHistoryError.accountChanged }
        try ConfirmedSpeciesReviewPersistence.transaction {
            try Self.validate(ticket: ticket, snapshot: nil, context: ModelContext(container))
        }
        let lease = try cloud.begin(ownerID)
        defer { cloud.finish(lease) }
        guard current(), lease.session.userID == ownerID, cloud.isCurrent(lease) else {
            throw ObservationHistoryError.accountChanged
        }
        let snapshot = try await fetch(.init(observationID: observationID, analysisID: analysisID), ownerID)
        guard current(), cloud.isCurrent(lease) else { throw ObservationHistoryError.accountChanged }
        guard snapshot.observationID == observationID, snapshot.analysisID == analysisID else {
            throw MerianError.invalidResponse
        }
        try ConfirmedSpeciesReviewPersistence.transaction {
            try Self.validate(ticket: ticket, snapshot: snapshot, context: ModelContext(container))
        }
        return Prepared(ticket: ticket, snapshot: snapshot)
    }

    @discardableResult
    func stage(_ acceptance: Acceptance, container: ModelContainer, isCurrent: () -> Bool) throws -> ObservationPublicationIntent {
        let prepared = acceptance.prepared, snapshot = prepared.snapshot
        let intent = try ObservationPublicationPersistence.stage(acceptance.request, ownerID: prepared.ownerID,
            container: container, isCurrent: isCurrent, validateNew: { context in
                try Self.validate(ticket: prepared.ticket, snapshot: snapshot, context: context)
            }, save: save)
        if !intent.isTerminal { wake() }
        return intent
    }

    private static func validate(ticket: ObservationAnalysisReviewTicket,
                                 snapshot: ObservationPublicationConsentSnapshot?, context: ModelContext) throws {
        guard ticket.supportsPhotoPublicationFormat else { throw ObservationHistoryError.unavailable }
        let observationID = ticket.observationID, analysisID = ticket.analysisID, ownerID = ticket.ownerID
        let scan = try ObservationHistorySyncService.enrolledScan(observationID.uuidString, context: context)
        guard scan.analysisOwnerAccountID == ownerID.uuidString.lowercased(),
              !(try ObservationHistoryEnrollmentIntent.holds(scan.id, context: context)) else {
            throw ObservationHistoryError.unavailable
        }
        try ObservationHistorySelectionIntent.requireIdle(scan.id, context: context)
        try ObservationHistoryStateSyncService.requireSettledReview(scan, context: context)
        try requireCompletedAnalysisReviews(observationID: observationID, ownerID: ownerID, context: context)
        guard try ObservationAnalysisReviewAdmission.currentTicket(ticket, scan: scan, context: context) == ticket else {
            throw ObservationHistoryPreviewService.AdmissionError.refreshRequired
        }
        let target = try ObservationHistorySelectionProjection.retained(analysisID, scan: scan, context: context)
        guard target.observationRevision == scan.observationStateRevision else {
            throw ObservationHistoryPreviewService.AdmissionError.refreshRequired
        }
        if let snapshot {
            guard snapshot.observationID == observationID, snapshot.analysisID == analysisID,
                  ticket.observationRevision == snapshot.expectedObservationRevision,
                  ticket.reviewRevision == snapshot.expectedReviewRevision else {
                throw ObservationHistoryPreviewService.AdmissionError.refreshRequired
            }
        }
    }

    /// This caller already owns the persistence lock. Do not call the public
    /// status reader here or broaden legacy settlement (review recovery uses it).
    private static func requireCompletedAnalysisReviews(observationID: UUID, ownerID: UUID, context: ModelContext) throws {
        let scope = ObservationAnalysisReviewPersistence.observationPrefix(observationID)
        for job in try context.fetch(FetchDescriptor<OfflineJobRecord>()) where job.id.hasPrefix(scope)
            || (job.kindRaw == OfflineJobKind.observationAnalysisReviewSync.rawValue
                && job.subjectId?.lowercased() == observationID.uuidString.lowercased()) {
            let intent = try ObservationAnalysisReviewPersistence.restore(job)
            guard intent.ownerID == ownerID, intent.request.observationID == observationID, intent.isComplete else {
                throw ObservationHistoryError.unavailable
            }
        }
    }
}
