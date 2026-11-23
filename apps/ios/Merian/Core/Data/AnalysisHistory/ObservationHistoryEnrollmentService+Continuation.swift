import Foundation
import SwiftData

extension ObservationHistoryEnrollmentService {
    /// An acknowledged full initial result already has immutable provenance.
    /// Reopening reads that association; it cannot reenroll or select the
    /// original over a later analysis. Legacy V3 recovery remains separate.
    static func acknowledgedInitialBaseline(observation: UUID, owner: UUID,
                                            container: ModelContainer) throws -> UUID? {
        try ConfirmedSpeciesReviewPersistence.transaction {
            let context = ModelContext(container); context.autosaveEnabled = false
            return try acknowledgedInitialBaseline(observation: observation, owner: owner, context: context)?.association.baselineAnalysisID
        }
    }
    struct AcknowledgedInitialBaseline {
        let association: ObservationHistoryEnrollmentIntent.BaselineAssociation
        let result: ObservationHistoryPage.Result
    }

    /// Caller holds one shared persistence transaction. Separating this read
    /// avoids acquiring the nonrecursive review lock twice during release joins.
    static func acknowledgedInitialBaseline(observation: UUID, owner: UUID,
                                            context: ModelContext) throws -> AcknowledgedInitialBaseline? {
        guard !context.hasChanges, !context.container.mainContext.hasChanges else { throw AdmissionError.localStateChanged }
        guard let association = try ObservationHistoryEnrollmentIntent.baseline(
            observationID: observation, ownerID: owner, context: context) else { return nil }
        let lower = observation.uuidString.lowercased()
        let scan = try ObservationHistorySyncService.enrolledScan(lower, context: context)
        guard scan.id == lower, scan.analysisOwnerAccountID == owner.uuidString.lowercased(),
              try !ObservationHistoryEnrollmentIntent.holds(lower, context: context) else {
            throw AdmissionError.localStateChanged
        }
        try ObservationHistorySelectionIntent.requireIdle(lower, context: context)
        try ObservationHistoryStateSyncService.requireSettledReview(scan, context: context)
        try ObservationHistoryStateSyncService.requireSettledAnalysisReview(scan, context: context)
        let original = try ObservationHistoryListingService.entry(association.baselineAnalysisID, scan: scan, context: context).result
        guard association.snapshotSHA256 == ObservationHistoryEnrollmentIntent.baselineDigest(original.bytes) else {
            throw AdmissionError.reconciliationRequired
        }
        if original.version == 3 { return nil }
        guard association.version == 1, association.intentID != nil, association.provenance == nil,
              scan.mediaAuthorityRaw == SharedMediaCaptureAcceptance.mediaAuthority, scan.sharedMediaConsumerID == nil,
              original.version == 8, original.initialEvidence?.ownerID == owner,
              original.analysisID == association.baselineAnalysisID else { throw AdmissionError.reconciliationRequired }
        // Validate the selected child independently. The returned value is
        // historical identity only and never current display authority.
        let selected = try ObservationHistoryPage.uuid(scan.selectedAnalysisID)
        _ = try ObservationHistoryListingService.entry(selected, scan: scan, context: context)
        guard !context.hasChanges else { throw AdmissionError.localStateChanged }
        return .init(association: association, result: original)
    }

}
