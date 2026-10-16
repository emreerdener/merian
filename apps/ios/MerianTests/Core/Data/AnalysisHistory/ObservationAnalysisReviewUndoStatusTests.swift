import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationAnalysisReviewUndoStatusTests {
    let support = ObservationAnalysisReviewReconciliationTests()
    typealias Store = ObservationAnalysisReviewPersistence

    @Test(arguments: ["complete", "unreconciled", "later_review", "other_association", "missing"])
    func undoNeedsCompletedExactRejectAndCurrentAssociation(mode: String) async throws {
        let (container, claim) = try await support.seeded()
        var row = try #require(JSONSerialization.jsonObject(with: support.targetData()) as? [String: Any])
        var item = try #require(row["analysis"] as? [String: Any])
        var review = try #require(item["review_snapshot"] as? [String: Any])
        var ai = try #require(review["ai_identification_review"] as? [String: Any])
        ai["operation_id"] = (mode == "other_association" ? UUID() : claim.intent.request.operationID).uuidString.lowercased()
        review["ai_identification_review"] = ai; item["review_snapshot"] = review
        if mode == "later_review" { item["review_revision"] = 2 }
        row["analysis"] = item
        let service = try ObservationAnalysisReviewReconciliation(cloud: support.cloud(
            targetData: JSONSerialization.data(withJSONObject: row), selectedData: support.selectedData()), now: { support.date })
        let complete = try await service.reconcile(claim, container: container, isCurrent: { true })
        let context = ModelContext(container)
        let scan = try ObservationHistorySyncService.enrolledScan(support.observation.uuidString, context: context)
        let entry = try ObservationHistoryListingService.entry(support.target, scan: scan, context: context)
        let ticket = try ObservationAnalysisReviewTicket(entry: entry,
            context: .init(owner: support.owner, selected: support.selected, revision: 12, pendingOperation: nil, undoOperation: nil),
            observationID: support.observation)
        let job = try #require(try context.fetchOfflineJob(id: Store.jobID(complete.request.operationID, observationID: support.observation)))
        if mode == "unreconciled" {
            job.metadataJSON = String(decoding: try claim.intent.storedData(), as: UTF8.self)
            job.status = .waiting
        } else if mode == "missing" { context.delete(job) }
        try context.save()
        let undo = try ObservationAnalysisReviewStatus.undoOperation(ticket, container: container, isCurrent: { true })
        #expect(undo == (mode == "complete" ? claim.intent.request.operationID : nil))
        if mode == "complete" {
            let status = try ObservationAnalysisReviewStatus.read(operationID: complete.request.operationID, ownerID: support.owner,
                observationID: support.observation, analysisID: support.target, container: container, isCurrent: { true })
            #expect(status?.phase == .complete(.applied(observationRevision: 11, reviewRevision: 1)))
            let request = try ticket.request(.undo(rejectionOperationID: claim.intent.request.operationID), operationID: UUID())
            let pending = try ObservationAnalysisReviewAdmission.stage(request, ticket: ticket, container: container, isCurrent: { true })
            #expect(pending.request == request && !pending.hasReceipt)
            #expect(try support.projection.parent(container).selectedAnalysisID == support.selected.uuidString.lowercased())
        }
    }
}
