#if DEBUG
import Foundation
import Observation
import SwiftData

/// Exact synthetic server response; staging, claims and paired reconciliation remain real.
@MainActor @Observable
final class CandidateConfirmationUIFixture {
    private let delivery = ObservationAnalysisReviewDeliveryOwner()
    private let lookup = ObservationConfirmationUndoOwner()
    private var applied: ObservationAnalysisReviewRequest?
    private var response: ObservationAnalysisReviewReceipt?
    private(set) var revision = 1
    private(set) var generation: UInt64 = 0

    var undoConfiguration: IdentificationHistoryReviewAccess.ConfirmationUndoConfiguration {
        .init(owner: lookup, fetch: { _, _, validate in
            try validate()
            // This journey must use its completed local candidate receipt.
            throw ObservationHistoryError.resultConflict
        })
    }
    func reviewRevision(_ analysis: String) -> Int { applied?.analysisID.uuidString.lowercased() == analysis ? 1 : 0 }
    func authority(_ analysis: String) -> [String: Any]? {
        guard let applied, applied.analysisID.uuidString.lowercased() == analysis else { return nil }
        return ["user_review_state": "user_overridden", "user_confirmed_identification": false,
            "user_identification_override": "Limenitis archippus",
            "confirmed_species_identity": ["version": 1, "species_id": "00000000-0000-4000-8000-00000000000b",
                "scientific_name": "Limenitis archippus", "common_name": NSNull(), "gbif_taxon_key": 1],
            "confirmed_species_identity_revision": 1, "confirmed_species_id": "00000000-0000-4000-8000-00000000000b",
            "ai_identification_review": ["version": 1, "revision": 1, "state": "clear",
                "origin_scan_id": PublicationConsentUIFixture.observation, "origin_identification": NSNull(),
                "operation_id": applied.operationID.uuidString.lowercased(),
                "operation_digest": String(repeating: "a", count: 32), "community": NSNull()]]
    }

    func wake(container: ModelContainer, cloud: ObservationHistoryCloudClient, snapshots: [String: Data]) {
        let service = ObservationAnalysisReviewDeliveryService(cloud: cloud, submit: { [self] request, owner, validate in
            try validate()
            let expected = try ObservationAnalysisCandidateReference(analysisID: request.analysisID, ordinal: 1,
                scientificName: "Limenitis archippus")
            guard owner == PublicationConsentUIFixture.owner,
                  request.observationID.uuidString.lowercased() == PublicationConsentUIFixture.observation,
                  request.analysisID.uuidString.lowercased() == PublicationConsentUIFixture.selected,
                  request.expectedObservationRevision == 1, request.expectedReviewRevision == 0,
                  request.decision == .confirmCandidate(expected) else { throw ObservationHistoryError.resultConflict }
            if let applied {
                guard applied == request, let response else { throw ObservationHistoryError.resultConflict }
                return response
            }
            guard var row = try JSONSerialization.jsonObject(with: request.encoded()) as? [String: Any] else {
                throw ObservationHistoryError.invalidSnapshot
            }
            row["outcome"] = "applied"; row["observation_revision"] = 2; row["review_revision"] = 1
            let receipt = try ObservationAnalysisReviewReceipt.decode(JSONSerialization.data(withJSONObject: row), request: request)
            applied = request; response = receipt; revision = 2
            return receipt
        })
        delivery.start(operation: { current in
            await ObservationAnalysisReviewDrain(cloud: cloud, deliver: service.deliver)
                .run(ownerID: PublicationConsentUIFixture.owner, container: container, isCurrent: current,
                     didStart: {}, requestRetry: { assertionFailure("Synthetic candidate confirmation must not need fallback") })
        }, didFinish: { [self] in
            if applied != nil { assert((try? verifyCompletion(container, snapshots: snapshots)) == true, "Candidate persistence mismatch") }
            generation &+= 1
        })
    }

    private func verifyCompletion(_ container: ModelContainer, snapshots: [String: Data]) throws -> Bool {
        guard let applied else { return false }
        let context = ModelContext(container)
        let jobs = try context.fetch(FetchDescriptor<OfflineJobRecord>()).filter { $0.kind == .observationAnalysisReviewSync }
        guard jobs.count == 1, let job = jobs.first else { return false }
        let intent = try ObservationAnalysisReviewPersistence.restore(job)
        guard intent.isComplete, intent.request == applied, intent.receipt == response,
              intent.receipt?.outcome == .applied(observationRevision: 2, reviewRevision: 1) else { return false }
        let scan = try ObservationHistorySyncService.enrolledScan(PublicationConsentUIFixture.observation, context: context)
        guard scan.selectedAnalysisID == PublicationConsentUIFixture.selected,
              let records = scan.analysisRecords, records.count == snapshots.count,
              Set(records.map(\.id)) == Set(snapshots.keys) else { return false }
        return records.allSatisfy { snapshots[$0.id] == $0.resultSnapshotData }
    }
}
#endif
