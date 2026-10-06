import Foundation
import SwiftData

/// Minimal local projection. A terminal receipt describes an operation, never
/// current identification authority. No raw metadata or automatic hold rearm.
struct ObservationAnalysisReviewStatus: Equatable {
    enum Phase: Equatable { case pending, reconciling, needsAttention, complete(ObservationAnalysisReviewReceipt.Outcome) }
    let operationID: UUID
    let analysisID: UUID
    let phase: Phase

    @MainActor
    static func read(operationID: UUID, ownerID: UUID, observationID: UUID, analysisID: UUID,
                     container: ModelContainer, isCurrent: () -> Bool) throws -> Self? {
        try scoped(ownerID: ownerID, observationID: observationID, container: container, isCurrent: isCurrent) { _, context in
            guard let job = try context.fetchOfflineJob(id: ObservationAnalysisReviewPersistence.jobID(operationID, observationID: observationID)) else { return nil }
            let intent = try ObservationAnalysisReviewPersistence.restore(job)
            guard intent.ownerID == ownerID, intent.request.analysisID == analysisID else { throw ObservationHistoryError.unavailable }
            try requireTarget(intent, context: context)
            return try projection(job, intent: intent)
        }
    }

    /// Blocks new decisions for this observation even when another target owns the
    /// unfinished operation. The caller only receives its identity and phase.
    @MainActor
    static func pending(ownerID: UUID, observationID: UUID, container: ModelContainer, isCurrent: () -> Bool) throws -> Self? {
        try scoped(ownerID: ownerID, observationID: observationID, container: container, isCurrent: isCurrent) { _, context in
            let prefix = ObservationAnalysisReviewPersistence.observationPrefix(observationID)
            var pending: Self?
            for job in try context.fetch(FetchDescriptor<OfflineJobRecord>()) where job.id.hasPrefix(prefix) {
                let intent = try ObservationAnalysisReviewPersistence.restore(job)
                guard intent.ownerID == ownerID else { throw ObservationHistoryError.unavailable }
                if !intent.isComplete {
                    try requireTarget(intent, context: context)
                    guard pending == nil else { throw ObservationHistoryError.resultConflict }
                    pending = try projection(job, intent: intent)
                }
            }
            return pending
        }
    }

    @MainActor
    static func undoOperation(_ ticket: ObservationAnalysisReviewTicket, container: ModelContainer, isCurrent: () -> Bool) throws -> UUID? {
        try scoped(ownerID: ticket.ownerID, observationID: ticket.observationID, container: container, isCurrent: isCurrent) { scan, context in
            guard try ObservationAnalysisReviewAdmission.currentTicket(ticket, scan: scan, context: context) == ticket else {
                throw ObservationHistoryError.resultConflict
            }
            return try undoOperation(ticket, context: context)
        }
    }

    static func undoOperation(_ ticket: ObservationAnalysisReviewTicket, context: ModelContext) throws -> UUID? {
        guard let operationID = ticket.rejectionOperationID,
              let job = try context.fetchOfflineJob(id: ObservationAnalysisReviewPersistence.jobID(operationID, observationID: ticket.observationID)) else { return nil }
        let intent = try ObservationAnalysisReviewPersistence.restore(job)
        guard intent.ownerID == ticket.ownerID, intent.request.analysisID == ticket.analysisID,
              intent.request.decision == .reject, intent.isComplete, let receipt = intent.receipt,
              case let .applied(observationRevision, reviewRevision) = receipt.outcome,
              observationRevision <= ticket.observationRevision, reviewRevision == ticket.reviewRevision else { return nil }
        return operationID
    }

    private static func requireTarget(_ intent: ObservationAnalysisReviewIntent, context: ModelContext) throws {
        let id = intent.request.analysisID.uuidString.lowercased()
        var query = FetchDescriptor<LocalAnalysisRecord>(predicate: #Predicate { $0.id == id })
        query.fetchLimit = 1
        guard let child = try context.fetch(query).first,
              child.ownerAccountID == intent.ownerID.uuidString.lowercased(),
              child.observationID.lowercased() == intent.request.observationID.uuidString.lowercased() else {
            throw ObservationHistoryError.unavailable
        }
    }

    private static func projection(_ job: OfflineJobRecord, intent: ObservationAnalysisReviewIntent) throws -> Self {
        let phase: Phase
        if intent.isComplete, let receipt = intent.receipt { phase = .complete(receipt.outcome) } else if job.status == .needsAttention { phase = .needsAttention } else {
            guard try ObservationAnalysisReviewPersistence.runnableShape(job, intent: intent) else { throw ObservationHistoryError.resultConflict }
            phase = intent.hasReceipt ? .reconciling : .pending
        }
        return Self(operationID: intent.request.operationID, analysisID: intent.request.analysisID, phase: phase)
    }

    @MainActor
    private static func scoped<T>(ownerID: UUID, observationID: UUID, container: ModelContainer,
                                  isCurrent: () -> Bool, body: (LocalScanRecord, ModelContext) throws -> T) throws -> T {
        try ConfirmedSpeciesReviewPersistence.transaction {
            guard isCurrent() else { throw ObservationHistoryError.accountChanged }
            let context = ModelContext(container)
            let scan = try ObservationHistorySyncService.enrolledScan(observationID.uuidString, context: context)
            guard scan.analysisOwnerAccountID == ownerID.uuidString.lowercased(),
                  !(try ObservationHistoryEnrollmentIntent.holds(scan.id, context: context)) else { throw ObservationHistoryError.unavailable }
            let value = try body(scan, context)
            try Task.checkCancellation()
            guard isCurrent() else { throw ObservationHistoryError.accountChanged }
            return value
        }
    }
}
