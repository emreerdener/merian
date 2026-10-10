import Foundation
import SwiftData

/// Exact local operation receipt, not publication visibility or current authority.
struct ObservationPublicationOperationStatus: Equatable {
    enum Phase: Equatable {
        case pending, reconciling, needsAttention
        case complete(ObservationPublicationStatus)
    }
    let operationID: UUID
    let analysisID: UUID
    let phase: Phase

    @MainActor
    static func read(operationID: UUID, ownerID: UUID, observationID: UUID, analysisID: UUID,
                     container: ModelContainer, isCurrent: () -> Bool) throws -> Self? {
        try scopedRead(ownerID: ownerID, observationID: observationID, container: container, isCurrent: isCurrent) { context, scan in
            try validateChild(analysisID, ownerID: ownerID, observationID: scan.id, context: context)
            guard let job = try context.fetchOfflineJob(id: ObservationPublicationPersistence.jobID(operationID, observationID: observationID)) else { return nil }
            let intent = try ObservationPublicationPersistence.restore(job)
            guard intent.ownerID == ownerID, intent.identity.operationID == operationID,
                  intent.identity.observationID == observationID, intent.identity.analysisID == analysisID else {
                throw ObservationHistoryError.unavailable
            }
            return try projection(job, intent: intent)
        }
    }

    /// Resolve the original local intake across historical targets. Multiple or
    /// malformed rows require reconciliation, never a latest-row guess or new ID.
    @MainActor
    static func readTarget(ownerID: UUID, observationID: UUID, container: ModelContainer,
                           isCurrent: () -> Bool) throws -> Self? {
        try scopedRead(ownerID: ownerID, observationID: observationID, container: container, isCurrent: isCurrent) { context, scan in
            guard let job = try ObservationPublicationPersistence.targetJob(ownerID: ownerID, observationID: observationID, context: context) else { return nil }
            let intent = try ObservationPublicationPersistence.restore(job)
            try validateChild(intent.identity.analysisID, ownerID: ownerID, observationID: scan.id, context: context)
            return try projection(job, intent: intent)
        }
    }

    private static func validateChild(_ analysisID: UUID, ownerID: UUID, observationID: String, context: ModelContext) throws {
        let childID = analysisID.uuidString.lowercased()
        var query = FetchDescriptor<LocalAnalysisRecord>(predicate: #Predicate { $0.id == childID })
        query.fetchLimit = 1
        guard let child = try context.fetch(query).first,
              child.ownerAccountID == ownerID.uuidString.lowercased(), child.observationID == observationID else {
            throw ObservationHistoryError.unavailable
        }
    }

    private static func projection(_ job: OfflineJobRecord, intent: ObservationPublicationIntent) throws -> Self {
        let status = try ObservationPublicationPersistence.validatedStatus(job, intent: intent)
        let phase: Phase
        if intent.isTerminal, let receipt = intent.receipt { phase = .complete(receipt.status) } else if status == .needsAttention || job.attemptCount >= Int.max - 1 {
            phase = .needsAttention
        } else { phase = intent.receipt == nil ? .pending : .reconciling }
        return Self(operationID: intent.identity.operationID, analysisID: intent.identity.analysisID, phase: phase)
    }

    @MainActor
    private static func scopedRead(ownerID: UUID, observationID: UUID, container: ModelContainer, isCurrent: () -> Bool,
                                   read: (ModelContext, LocalScanRecord) throws -> Self?) throws -> Self? {
        try ConfirmedSpeciesReviewPersistence.transaction {
            guard isCurrent() else { throw ObservationHistoryError.accountChanged }
            let context = ModelContext(container)
            let scan = try ObservationHistorySyncService.enrolledScan(observationID.uuidString, context: context)
            guard scan.analysisOwnerAccountID == ownerID.uuidString.lowercased(),
                  !(try ObservationHistoryEnrollmentIntent.holds(scan.id, context: context)) else {
                throw ObservationHistoryError.unavailable
            }
            let value = try read(context, scan)
            try Task.checkCancellation()
            guard isCurrent() else { throw ObservationHistoryError.accountChanged }
            return value
        }
    }
}
