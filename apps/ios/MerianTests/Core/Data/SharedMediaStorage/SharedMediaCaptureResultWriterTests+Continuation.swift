import Foundation
@testable import Merian
import SwiftData
import Testing

extension SharedMediaCaptureResultWriterTests {
    func verifyAcknowledgedContinuation(plan: CaptureInitialEvidencePlan, analysis: String,
                                        container: ModelContainer, cloud: ObservationHistoryCloudClient) async throws {
        let id = plan.scanID.uuidString.lowercased(), originalID = try #require(UUID(uuidString: analysis))
        let read = {
            try ObservationHistoryEnrollmentService.acknowledgedInitialBaseline(
                observation: plan.scanID, owner: plan.ownerID, container: container)
        }
        #expect(throws: (any Error).self) {
            try ObservationHistoryEnrollmentService.acknowledgedInitialBaseline(observation: plan.scanID, owner: UUID(), container: container)
        }
        let context = ModelContext(container); context.autosaveEnabled = false
        let parent = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        let baseline = try #require(try context.fetchOfflineJob(id: ObservationHistoryEnrollmentIntent.baselineJobID(id)))
        let metadata = baseline.metadataJSON
        baseline.metadataJSON = "{}"; try context.save()
        #expect(throws: (any Error).self) { try read() }
        baseline.metadataJSON = metadata; try context.save()

        // Corruption is seeded as a separate immutable record. Production
        // snapshot setters remain private and the valid original is untouched.
        let malformedID = UUID()
        let metadataText = try #require(metadata)
        var association = try #require(JSONSerialization.jsonObject(with: Data(metadataText.utf8)) as? [String: Any])
        association["baselineAnalysisID"] = malformedID.uuidString
        baseline.metadataJSON = String(decoding: try JSONSerialization.data(withJSONObject: association, options: [.sortedKeys]), as: UTF8.self)
        try context.save()
        #expect(throws: (any Error).self) { try read() } // Missing original.
        let malformed = try LocalAnalysisRecord(analysisID: malformedID, observationID: id,
            ownerAccountID: plan.ownerID, completedAt: Date(), snapshotVersion: 8, resultSnapshotData: Data("{}".utf8))
        context.insert(malformed); parent.analysisRecords?.append(malformed); try context.save()
        #expect(throws: (any Error).self) { try read() } // Malformed original.
        baseline.metadataJSON = metadata
        parent.analysisRecords?.removeAll { $0.id == malformedID.uuidString.lowercased() }
        context.delete(malformed); try context.save()

        let deletion = PendingCloudDeletionTask(scanId: id)
        context.insert(deletion); try context.save()
        #expect(throws: (any Error).self) { try read() }
        context.delete(deletion); try context.save()
        let hold = OfflineJobRecord(id: ObservationHistoryEnrollmentIntent.jobID(id), kind: .future,
            subjectId: id, status: .needsAttention, metadataJSON: "{}")
        context.insert(hold); try context.save()
        #expect(throws: (any Error).self) { try read() }
        context.delete(hold); try context.save()

        // Simulate an already acknowledged later selected result. Continuation
        // must retain both this selection and mutable review/display state.
        let response = try ObservationHistorySelectionSyncTests().nativeResponse()
        let state = try #require(JSONSerialization.jsonObject(with: response) as? [String: Any])
        let selected = try #require(state["analysis"] as? [String: Any])
        let text = try #require(selected["snapshot"] as? String)
        var snapshot = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        let nextID = UUID()
        snapshot["observation_id"] = id; snapshot["analysis_id"] = nextID.uuidString.lowercased()
        snapshot["source_analysis_id"] = analysis
        var result = try #require(snapshot["result"] as? [String: Any]); result["scan_id"] = id; snapshot["result"] = result
        let next = try ObservationHistoryPage.snapshot(JSONSerialization.data(withJSONObject: snapshot), observationID: id, ordinal: 2)
        _ = try ObservationHistorySyncService.insert([next], into: parent, ownerID: plan.ownerID, context: context)
        parent.selectedAnalysisID = nextID.uuidString.lowercased()
        parent.observationStateRevision = 8
        parent.fieldNotes = "Synthetic later private note"
        try context.save()
        let before = ObservationHistoryStateSyncService.ReviewBaseline(parent, displayAnalysisID: nextID)
        #expect(try await ObservationHistoryEnrollmentOwner().continueInitialHistory(observation: plan.scanID,
            owner: plan.ownerID, generation: 2, container: container, cloud: cloud, isCurrent: { true }) == originalID)
        let after = try #require(ModelContext(container).fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(ObservationHistoryStateSyncService.ReviewBaseline(after, displayAnalysisID: nextID) == before)
        #expect(after.fieldNotes == "Synthetic later private note")
    }
}
