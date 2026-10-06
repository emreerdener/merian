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
        try ConfirmedSpeciesReviewPersistence.transaction {
            guard isCurrent() else { throw ObservationHistoryError.accountChanged }
            let context = ModelContext(container)
            let scan = try ObservationHistorySyncService.enrolledScan(observationID.uuidString, context: context)
            guard scan.analysisOwnerAccountID == ownerID.uuidString.lowercased(),
                  !(try ObservationHistoryEnrollmentIntent.holds(scan.id, context: context)) else {
                throw ObservationHistoryError.unavailable
            }
            let childID = analysisID.uuidString.lowercased()
            var query = FetchDescriptor<LocalAnalysisRecord>(predicate: #Predicate { $0.id == childID })
            query.fetchLimit = 1
            guard let child = try context.fetch(query).first,
                  child.ownerAccountID == ownerID.uuidString.lowercased(), child.observationID == scan.id else {
                throw ObservationHistoryError.unavailable
            }
            let value: Self?
            if let job = try context.fetchOfflineJob(id: ObservationPublicationPersistence.jobID(operationID, observationID: observationID)) {
                let intent = try ObservationPublicationPersistence.restore(job)
                guard intent.ownerID == ownerID, intent.identity.operationID == operationID,
                      intent.identity.observationID == observationID, intent.identity.analysisID == analysisID else {
                    throw ObservationHistoryError.unavailable
                }
                let status = try ObservationPublicationPersistence.validatedStatus(job, intent: intent)
                let phase: Phase
                if intent.isTerminal, let receipt = intent.receipt { phase = .complete(receipt.status) } else if status == .needsAttention || job.attemptCount >= Int.max - 1 {
                    phase = .needsAttention
                } else { phase = intent.receipt == nil ? .pending : .reconciling }
                value = Self(operationID: operationID, analysisID: analysisID, phase: phase)
            } else { value = nil }
            try Task.checkCancellation()
            guard isCurrent() else { throw ObservationHistoryError.accountChanged }
            return value
        }
    }
}
