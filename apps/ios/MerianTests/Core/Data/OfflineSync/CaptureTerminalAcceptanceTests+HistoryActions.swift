import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
extension CaptureTerminalAcceptanceTests {
    // The server boundary is synthetic; admission, durable intents, projection,
    // acknowledgement and review reconciliation are the actual native owners.
    func exerciseCompletedChildActions(source: ObservationReanalysisSource, child: UUID,
        resultBytes: Data, container: ModelContainer, cloud: ObservationHistoryCloudClient,
        baselineState: [String: Any]) async throws {
        var phase = "verify completion authority"
        defer { if phase != "complete" { print("Capture History actions stopped at " + phase) } }
        let completionContext = ModelContext(container)
        let erasureJob = try #require(try completionContext.fetchOfflineJob(
            id: ObservationReanalysisErasureReceipt.jobID(child)))
        #expect(try ObservationReanalysisErasureReceipt.restore(erasureJob)
            == .init(parentID: source.observationID, childID: child))
        #expect(erasureJob.status == .pending)
        #expect(try completionContext.fetchOfflineJob(id: OfflineQueueManager.scanIngestionJobId(
            scanId: child.uuidString.lowercased())) == nil)
        // These tests leave staged-byte cleanup pending. They qualify durable
        // cleanup authority, not the separate erasure scheduler or process exit.
        let observation = source.observationID.uuidString.lowercased()
        let original = source.analysisID.uuidString.lowercased()
        let childID = child.uuidString.lowercased()
        let snapshots = [original: source.snapshot, childID: resultBytes]
        var selected = original, revision = 1, reviewRevision = 0
        var latestReview: ObservationAnalysisReviewIntent?
        var cleared = false
        var historyCloud = cloud
        historyCloud.fetchState = { request in
            let target = request.analysis_id ?? selected
            var state = baselineState
            state["selected_analysis_id"] = selected
            state["state_revision"] = revision
            var analysis = try #require(state["analysis"] as? [String: Any])
            analysis["snapshot"] = String(decoding: try #require(snapshots[target]), as: UTF8.self)
            analysis["review_revision"] = target == childID ? reviewRevision : 0
            if target == childID, let latestReview {
                var authority = try #require(analysis["review_snapshot"] as? [String: Any])
                authority["ai_identification_review"] = ["version": 1, "revision": reviewRevision,
                    "state": cleared ? "clear" : "ai_rejected", "origin_scan_id": observation,
                    "origin_identification": NSNull(),
                    "operation_id": latestReview.request.operationID.uuidString.lowercased(),
                    "operation_digest": String(repeating: cleared ? "b" : "a", count: 32),
                    "community": NSNull()] as [String: Any]
                authority["confirmed_species_identity_revision"] = reviewRevision
                analysis["review_snapshot"] = authority
            }
            state["analysis"] = analysis
            return try JSONSerialization.data(withJSONObject: state, options: [.sortedKeys])
        }
        var receipts: [String: Data] = [:]
        var requests: [ObservationHistorySelectionRequest] = []
        var loseReply = true
        historyCloud.select = { request in
            requests.append(request)
            if let receipt = receipts[request.operation_id] { return receipt }
            #expect(request.expected_observation_revision == revision)
            let previous = selected
            selected = request.analysis_id; revision += 1
            let receipt = try JSONEncoder().encode(ObservationHistorySelectionReceipt(schema_version: 1,
                operation_id: request.operation_id, observation_id: request.observation_id,
                previous_analysis_id: previous, selected_analysis_id: selected,
                observation_revision: revision, review_revision: request.expected_review_revision))
            receipts[request.operation_id] = receipt
            if loseReply { loseReply = false; throw ObservationHistoryError.unavailable }
            return receipt
        }
        let preview = try await ObservationHistoryPreviewService(cloud: historyCloud).preview(
            observationID: observation, analysisID: child, container: container)
        #expect(!preview.isSelected && preview.state.result.bytes == resultBytes)
        let selection = ObservationHistorySelectionService(cloud: historyCloud)
        let request = try selection.prepare(observationID: observation, analysisID: child,
            ownerID: source.ownerID, container: container)
        await #expect(throws: ObservationHistoryError.unavailable) {
            try await selection.sendPending(observationID: observation, container: container)
        }
        _ = try await selection.sendPending(observationID: observation, container: container)
        #expect(requests == [request, request])
        let listing = ObservationHistoryListingService(cloud: historyCloud)
        func ticket() throws -> ObservationAnalysisReviewTicket {
            try .init(entry: listing.cached(observationID: observation, analysisID: child, container: container),
                context: listing.context(observationID: observation, container: container), observationID: source.observationID)
        }
        func settleReview(_ intent: ObservationAnalysisReviewIntent, undo: Bool) async throws {
            typealias Store = ObservationAnalysisReviewPersistence
            let now = Date()
            let claim = try #require(try Store.claim(intent, at: now, container: container, isCurrent: { true }))
            #expect(intent.request.expectedObservationRevision == revision)
            #expect(intent.request.expectedReviewRevision == reviewRevision)
            let receipt = try ObservationAnalysisReviewPersistenceTests().receipt(intent.request)
            #expect(receipt.outcome == .applied(observationRevision: revision + 1, reviewRevision: reviewRevision + 1))
            let acknowledged = try Store.acknowledge(receipt, claim: claim, at: now,
                container: container, isCurrent: { true })
            revision += 1; reviewRevision += 1; latestReview = intent; cleared = undo
            let reconcile = try #require(try Store.claim(acknowledged, at: now, container: container, isCurrent: { true }))
            let complete = try await ObservationAnalysisReviewReconciliation(cloud: historyCloud).reconcile(
                reconcile, container: container, isCurrent: { true })
            #expect(complete.isComplete)
        }
        phase = "review selected child"
        let displayed = try ticket()
        #expect(displayed.selectedAnalysisID == child && displayed.canReject)
        let rejected = try ObservationAnalysisReviewAdmission.stage(displayed.request(.reject, operationID: UUID()),
            ticket: displayed, container: container, isCurrent: { true })
        try await settleReview(rejected, undo: false)
        let reviewed = try ticket()
        #expect(reviewed.rejectionOperationID == rejected.request.operationID)
        let undo = try ObservationAnalysisReviewAdmission.stage(
            reviewed.request(.undo(rejectionOperationID: rejected.request.operationID), operationID: UUID()),
            ticket: reviewed, container: container, isCurrent: { true })
        try await settleReview(undo, undo: true)
        #expect(try ticket().reviewState == .unreviewed)
        phase = "return to baseline and Undo"
        // Review changes can invalidate a selection Undo CAS. Prepare a fresh
        // explicit return to the baseline, then prove its own Undo independently.
        _ = try await ObservationHistoryPreviewService(cloud: historyCloud).preview(
            observationID: observation, analysisID: source.analysisID, container: container)
        let returnRequest = try selection.prepare(observationID: observation, analysisID: source.analysisID,
            ownerID: source.ownerID, container: container)
        _ = try await selection.sendPending(observationID: observation, container: container)
        _ = try selection.prepareUndo(observationID: observation,
            operationID: #require(UUID(uuidString: returnRequest.operation_id)), ownerID: source.ownerID, container: container)
        _ = try await selection.sendPending(observationID: observation, container: container)
        #expect(try ticket().selectedAnalysisID == child)
        _ = try await ObservationHistoryPreviewService(cloud: historyCloud).preview(
            observationID: observation, analysisID: source.analysisID, container: container)
        _ = try selection.prepare(observationID: observation, analysisID: source.analysisID,
            ownerID: source.ownerID, container: container)
        _ = try await selection.sendPending(observationID: observation, container: container)
        let fresh = ModelContext(container)
        let parent = try ObservationHistorySyncService.enrolledScan(observation, context: fresh)
        #expect(parent.selectedAnalysisID == original)
        #expect(try Dictionary(uniqueKeysWithValues: fresh.fetch(FetchDescriptor<LocalAnalysisRecord>())
            .map { ($0.id, $0.resultSnapshotData) }) == snapshots)
        #expect(try fresh.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
        phase = "complete"
    }
}
