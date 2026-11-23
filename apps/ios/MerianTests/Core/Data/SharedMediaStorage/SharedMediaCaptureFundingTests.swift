import Foundation
@testable import Merian
import SwiftData
import Testing

extension SharedMediaCaptureResultWriterTests {
    func selection(_ mode: String, plan: CaptureInitialEvidencePlan, container: ModelContainer) throws {
        let context = ModelContext(container); context.autosaveEnabled = false
        let scan = plan.scanID.uuidString.lowercased()
        let request = ObservationHistorySelectionRequest(observation: plan.scanID,
            analysis: UUID(), revision: 1, review: 0)
        var entry = ObservationHistorySelectionIntent.Entry(version: 2, owner: plan.ownerID.uuidString.lowercased(),
            previous: UUID().uuidString.lowercased(), previousReview: 0, request: request)
        if mode == "selectionReceipt" {
            entry.receipt = .init(schema_version: 1, operation_id: request.operation_id, observation_id: scan,
                previous_analysis_id: entry.previous, selected_analysis_id: request.analysis_id,
                observation_revision: 2, review_revision: 0)
        }
        if mode == "selectionRejected" {
            entry.rejection = .init(schema_version: 1, operation_id: request.operation_id, observation_id: scan,
                analysis_id: request.analysis_id, expected_observation_revision: 1,
                expected_review_revision: 0, outcome: "revision_conflict")
        }
        try ObservationHistorySelectionIntent.store(entry, context: context)
        if mode == "malformedSelection" {
            try context.fetchOfflineJob(id: ObservationHistorySelectionIntent.jobID(scan))?.metadataJSON = nil
        }
        try context.save()
    }

    private func fundedResponse(_ plan: CaptureInitialEvidencePlan, owner: UUID? = nil, version: Int = 1) throws -> Data {
        var object = try #require(JSONSerialization.jsonObject(with: response(plan)) as? [String: Any])
        object["entitlement"] = ["user_id": (owner ?? plan.ownerID).uuidString.lowercased(),
            "plan_used": "pro_paid", "credit_consumed": false,
            "entitlement_after": ["current_plan": "pro_paid", "current_tier": "pro", "is_paid": true,
                "scans_remaining": 0, "scans_available_to_start": 0, "in_flight_count": 0, "entitlement_version": version]]
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func fundingReceipt(_ plan: CaptureInitialEvidencePlan, container: ModelContainer) throws -> SharedMediaCaptureFundingReceipt {
        let context = ModelContext(container); context.autosaveEnabled = false
        let job = try #require(try context.fetchOfflineJob(id: OfflineQueueManager.scanIngestionJobId(scanId: plan.scanID.uuidString.lowercased())))
        #expect(job.status == .complete)
        return try .read(#require(job.metadataJSON))
    }

    @Test(arguments: [false, true])
    func fundingLostAcknowledgementReplaysOriginalAfterColdOpen(unrelatedDraft: Bool) async throws {
        let store = try await Store(), owner = try await store.open(), plan = try await prepare(store, owner: owner)
        try await stage(plan, owner: owner)
        let account = InferenceCompletionAccountScope(ownerID: plan.ownerID, isCurrent: { true }, release: {})
        defer { account.finish() }
        var calls = 0
        var escaped: SharedMediaCaptureResultWriter.FundingHandoff?
        await #expect(throws: SharedMediaStorageFailure.unavailable) {
            try await owner.completeAppCaptureSubmission(scanID: plan.scanID, submissionGeneration: plan.generation,
                attemptGeneration: plan.generation, resultData: fundedResponse(plan), account: account, settleFunding: { handoff in
                    try handoff.validate(); calls += 1; escaped = handoff
                    #expect(try ModelContext(store.container).fetchCount(FetchDescriptor<LocalScanRecord>()) == 1)
                    #expect(try !fundingReceipt(plan, container: store.container).delivered)
                    throw SharedMediaStorageFailure.unavailable
                })
        }
        #expect(throws: (any Error).self) { try #require(escaped).validate() }
        let original = try fundingReceipt(plan, container: store.container)
        #expect(!original.delivered && calls == 1)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await store.open(); try await cold.resumeAppCaptureRoot()
        // A newer response cannot replace the original completion's settlement.
        await #expect(throws: (any Error).self) {
            try await cold.completeAppCaptureSubmission(scanID: plan.scanID, submissionGeneration: plan.generation,
                attemptGeneration: plan.generation, resultData: fundedResponse(plan, version: 2), account: account,
                settleFunding: { _ in Issue.record("Changed settlement delivered") })
        }
        #expect(try fundingReceipt(plan, container: store.container) == original)
        try await cold.resumeAppCaptureRoot()
        let edited = ModelContext(store.container); edited.autosaveEnabled = false
        let record = try #require(edited.fetch(FetchDescriptor<LocalScanRecord>()).first)
        record.selectedAnalysisID = UUID().uuidString.lowercased()
        record.scientificName = "Later selected species"; record.userConfirmedIdentification = true
        record.fieldNotes = "Later private note"
        try edited.save()
        if unrelatedDraft {
            let pending = try CaptureInitialEvidencePlan(ownerID: plan.ownerID, scanID: UUID(), generation: UUID(), items: [
                .audio(.init(source: .init(mediaID: UUID(), contentType: "audio/wav", byteCount: store.bytes.count,
                    sha256: SharedMediaAcquisitionEncoding.digest(store.bytes)), preparedMediaID: UUID()))
            ])
            _ = try await cold.reserveAppCaptureSubmission(pending, context: SharedMediaCaptureSubmissionContextTests.context(pending))
            try await cold.resumeAppCaptureRoot()
            #expect(!cold.isReadyForCaptureDispatch && cold.isReadyForCaptureSettlement)
        }
        let page = try await cold.captureFundingRecoveryPage()
        #expect(page.nextCursor == nil && page.candidates.count == 1)
        let candidate = try #require(page.candidates.first)
        #expect(candidate.scanID == plan.scanID && candidate.generation == plan.generation && candidate.due == nil)
        let due = Date(timeIntervalSinceReferenceDate: 900_000_000)
        try await cold.postponeAppCaptureFunding(candidate, until: due)
        #expect(try await cold.captureFundingRecoveryPage().candidates.first?.due == due)
        // Receipt recovery needs no provider response or fresh execution.
        try await cold.recoverAppCaptureFunding(scanID: plan.scanID, submissionGeneration: plan.generation,
            account: account, settleFunding: { handoff in
                try handoff.validate(); calls += 1; escaped = handoff
                #expect(handoff.settlement.entitlementAfter.entitlementVersion == 1)
                #expect(handoff.settlement.accountId == plan.ownerID)
            })
        #expect(throws: (any Error).self) { try #require(escaped).validate() }
        #expect(try fundingReceipt(plan, container: store.container).delivered)
        #expect(try await cold.captureFundingRecoveryPage().candidates.isEmpty)
        let acknowledged = try #require(try ModelContext(store.container).fetchOfflineJob(
            id: OfflineQueueManager.scanIngestionJobId(scanId: plan.scanID.uuidString.lowercased())))
        #expect(acknowledged.status == .complete && acknowledged.nextRunAt == nil)
        let preserved = try #require(ModelContext(store.container).fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(preserved.scientificName == "Later selected species" && preserved.userConfirmedIdentification
            && preserved.fieldNotes == "Later private note" && preserved.selectedAnalysisID == record.selectedAnalysisID)
        #expect(try await cold.completeAppCaptureSubmission(scanID: plan.scanID, submissionGeneration: plan.generation,
            attemptGeneration: plan.generation, resultData: fundedResponse(plan), account: account,
            settleFunding: { _ in Issue.record("Acknowledged settlement redelivered") }) == .retained)
        #expect(calls == 2)
        #expect(try ModelContext(store.container).fetchCount(FetchDescriptor<LocalScanRecord>()) == 1)
        #expect(try ModelContext(store.container).fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 1)
        #expect(try store.rows().allSatisfy { $0.retirementData == nil })
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test func foreignFundingCannotCommitResultOrDeliverEffects() async throws {
        let store = try await Store(), owner = try await store.open(), plan = try await prepare(store, owner: owner)
        try await stage(plan, owner: owner)
        let account = InferenceCompletionAccountScope(ownerID: plan.ownerID, isCurrent: { true }, release: {})
        defer { account.finish() }
        await #expect(throws: (any Error).self) {
            try await owner.completeAppCaptureSubmission(scanID: plan.scanID, submissionGeneration: plan.generation,
                attemptGeneration: plan.generation, resultData: fundedResponse(plan, owner: UUID()), account: account,
                settleFunding: { _ in Issue.record("Foreign settlement delivered") })
        }
        #expect(try ModelContext(store.container).fetchCount(FetchDescriptor<LocalScanRecord>()) == 0)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }
}
