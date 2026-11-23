import Foundation
@testable import Merian
import SwiftData
import Testing

@Suite("Accepted Capture original release", .serialized, .sharedProcessState(.offlineQueueManager))
@MainActor
struct SharedMediaCaptureAcceptedReleaseTests {
    @MainActor struct Fixture {
        let store: SharedMediaCaptureArtifactWriterTests.Store
        let owner: SharedMediaNativeOriginalOwner
        let plan: CaptureInitialEvidencePlan
        let response: Data
        let analysis: String
        let cloud: ObservationHistoryCloudClient

        func snapshot() throws -> SharedMediaCaptureSubmissionReceipt.Snapshot {
            let context = ModelContext(store.container); context.autosaveEnabled = false
            return try #require(try SharedMediaCaptureSubmissionReceipt.auditMatching(scanID: plan.scanID, generation: plan.generation, in: context))
        }

        func enroll() async throws {
            #expect(try await ObservationHistoryEnrollmentService(cloud: cloud).enroll(observationID: plan.scanID.uuidString.lowercased(),
                expectedOwnerID: plan.ownerID, container: store.container) == UUID(uuidString: analysis))
        }
    }

    func fixture() async throws -> Fixture {
        let helper = SharedMediaCaptureResultWriterTests()
        let store = try await SharedMediaCaptureArtifactWriterTests.Store(), owner = try await store.open()
        let plan = try await helper.prepare(store, owner: owner)
        try await helper.stage(plan, owner: owner)
        let evidence = try helper.enrollmentFixture(plan)
        let account = InferenceCompletionAccountScope(ownerID: plan.ownerID, isCurrent: { true }, release: {})
        defer { account.finish() }
        _ = try await owner.completeAppCaptureSubmission(scanID: plan.scanID, submissionGeneration: plan.generation,
            attemptGeneration: plan.generation, resultData: evidence.response, account: account)
        let scan = plan.scanID.uuidString.lowercased(), analysis = try #require(evidence.snapshot["analysis_id"] as? String)
        var state = try ObservationHistoryStateTests().fixture()
        state["owner_id"] = plan.ownerID.uuidString.lowercased(); state["observation_id"] = scan; state["selected_analysis_id"] = analysis
        var child = try #require(state["analysis"] as? [String: Any])
        child["snapshot"] = try #require(String(data: JSONSerialization.data(withJSONObject: evidence.snapshot, options: [.sortedKeys]), encoding: .utf8))
        state["analysis"] = child
        let stateBytes = try JSONSerialization.data(withJSONObject: state)
        let receipt = try JSONSerialization.data(withJSONObject: ["schema_version": 1,
            "owner_id": plan.ownerID.uuidString.lowercased(), "observation_id": scan, "baseline_analysis_id": analysis])
        var cloud = ObservationHistoryCloudClient(begin: { owner in .init(id: UUID(), session: .init(userID: owner, isAnonymous: false)) },
            isCurrent: { _ in true }, finish: { _ in }, fetch: { _ in throw ObservationHistoryError.unavailable })
        cloud.enroll = { _ in Issue.record("Release fixture entered legacy enrollment"); throw ObservationHistoryError.unavailable }
        cloud.enrollInitial = { _ in receipt }; cloud.fetchState = { _ in stateBytes }
        return .init(store: store, owner: owner, plan: plan, response: evidence.response, analysis: analysis, cloud: cloud)
    }

    @Test(arguments: SharedMediaCaptureReleaseBoundary.allCases)
    func interruptedReleaseResumesWithoutRevivingAnyMember(_ point: SharedMediaCaptureReleaseBoundary) async throws {
        let fixture = try await fixture(), plan = fixture.plan
        try await fixture.enroll()
        let accepted = try fixture.snapshot()
        #expect(try await fixture.owner.captureCompletedRecoveryPage().candidates == [
            .init(scanID: plan.scanID, generation: plan.generation, releaseStarted: false)
        ])
        var reached = false
        try fixture.owner.configureCaptureAcceptedReleaseForTesting { current in
            if current == point { reached = true; throw SharedMediaStorageFailure.unavailable }
        }
        await #expect(throws: (any Error).self) {
            _ = try await fixture.owner.releaseAppCaptureSubmission(scanID: plan.scanID, generation: plan.generation)
        }
        #expect(reached)
        if point != .beforeIntentSave {
            #expect(throws: (any Error).self) {
                let context = ModelContext(fixture.store.container); context.autosaveEnabled = false
                _ = try SharedMediaCaptureReleaseQualification.read(accepted, context: context)
            }
            #expect(throws: (any Error).self) {
                let context = ModelContext(fixture.store.container); context.autosaveEnabled = false
                _ = try SharedMediaCaptureSubmissionReceipt.matching(scanID: plan.scanID, generation: plan.generation, in: context)
            }
        }
        #expect(await fixture.owner.invalidateAndAwaitForAccountTransition())
        let cold = try await fixture.store.open()
        let released = try await cold.releaseAppCaptureSubmission(scanID: plan.scanID, generation: plan.generation)
        #expect(released.releasedRevision != nil)
        #expect(try await cold.releaseAppCaptureSubmission(scanID: plan.scanID, generation: plan.generation) == released)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.store.directory.path).isEmpty)
        let saved = try fixture.snapshot()
        #expect(saved.artifacts.allSatisfy { $0.acceptedRelease?.releasedRevision != nil && $0.retirement == nil })
        #expect(saved.submission == accepted.submission && saved.state == accepted.state)
        #expect(try await cold.captureCompletedRecoveryPage().candidates.isEmpty)
        #expect(try await cold.captureFundingRecoveryPage().candidates.isEmpty)
        #expect(try await cold.captureExecutionRecoveryPage().candidates.isEmpty)
        let network = try ObservationSourceTransportTests.Fixture(); defer { network.close() }
        network.mock.register(path: "/upload-capture-stage") { _ in
            Issue.record("Released originals attempted an upload")
            throw SharedMediaStorageFailure.closed
        }
        await #expect(throws: (any Error).self) {
            _ = try await cold.stageAppCaptureSubmission(scanID: plan.scanID, generation: plan.generation,
                transport: .init(baseURL: "https://example.supabase.co", dispatcher: network.dispatcher))
        }
        #expect(cold.requiresCaptureRecovery)
        try await cold.resumeAppCaptureRoot()
        #expect(cold.isReadyForCaptureSettlement)
        let account = InferenceCompletionAccountScope(ownerID: plan.ownerID, isCurrent: { true }, release: {})
        defer { account.finish() }
        #expect(try await cold.completeAppCaptureSubmission(scanID: plan.scanID, submissionGeneration: plan.generation,
            attemptGeneration: plan.generation, resultData: fixture.response, account: account) == .retained)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test func completedContinuationUsesHistoryOwnerAndResumesCleanupWithoutEnrollment() async throws {
        let fixture = try await fixture(), plan = fixture.plan
        let history = ObservationHistoryEnrollmentOwner()
        var enrollmentCalls = 0
        let continuation = CaptureCompletedHistoryContinuation(requireCurrent: {}, inspect: { candidate in
            try await fixture.owner.inspectCompletedAppCapture(candidate)
        }, enroll: { observation in
            enrollmentCalls += 1
            let baseline = try await history.continueInitialHistory(observation: observation, owner: plan.ownerID,
                generation: 1, container: fixture.store.container, cloud: fixture.cloud, isCurrent: { true })
            #expect(baseline == UUID(uuidString: fixture.analysis))
        }, release: { candidate in
            _ = try await fixture.owner.releaseAppCaptureSubmission(scanID: candidate.scanID, generation: candidate.generation)
        })
        let candidate = try #require(try await fixture.owner.captureCompletedRecoveryPage().candidates.first)
        try fixture.owner.configureCaptureAcceptedReleaseForTesting { point in
            if point == .afterUnlink { throw SharedMediaStorageFailure.unavailable }
        }
        await #expect(throws: (any Error).self) { try await continuation.finish(candidate) }
        #expect(enrollmentCalls == 1)
        #expect(try fixture.snapshot().release?.releasedRevision == nil)
        try fixture.owner.configureCaptureAcceptedReleaseForTesting(nil)
        let pending = try #require(try await fixture.owner.captureCompletedRecoveryPage().candidates.first)
        #expect(pending.releaseStarted)
        try await continuation.finish(candidate)
        #expect(enrollmentCalls == 1)
        #expect(try fixture.snapshot().release?.releasedRevision != nil)
        try await continuation.finish(candidate)
        #expect(enrollmentCalls == 1)
        #expect(try await fixture.owner.captureCompletedRecoveryPage().candidates.isEmpty)
        #expect(await fixture.owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func completedContinuationRetainsOriginalsWhenAccountChangesAfterEnrollment() async throws {
        let fixture = try await fixture(), plan = fixture.plan
        let history = ObservationHistoryEnrollmentOwner()
        var current = true, released = false
        let continuation = CaptureCompletedHistoryContinuation(requireCurrent: {
            guard current else { throw SharedMediaStorageFailure.closed }
        }, inspect: { candidate in
            try await fixture.owner.inspectCompletedAppCapture(candidate)
        }, enroll: { observation in
            _ = try await history.continueInitialHistory(observation: observation, owner: plan.ownerID,
                generation: 1, container: fixture.store.container, cloud: fixture.cloud, isCurrent: { current })
            current = false
        }, release: { _ in released = true })
        let candidate = try #require(try await fixture.owner.captureCompletedRecoveryPage().candidates.first)
        await #expect(throws: (any Error).self) { try await continuation.finish(candidate) }
        #expect(!released)
        #expect(try fixture.snapshot().release == nil)
        #expect(try !FileManager.default.contentsOfDirectory(atPath: fixture.store.directory.path).isEmpty)
        #expect(await fixture.owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func completedContinuationRejectsMissingResultBeforeHistoryOrRelease() async throws {
        let fixture = try await fixture()
        let candidate = try #require(try await fixture.owner.captureCompletedRecoveryPage().candidates.first)
        let context = ModelContext(fixture.store.container); context.autosaveEnabled = false
        let scanID = fixture.plan.scanID.uuidString.lowercased()
        let record = try #require(try context.fetch(FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == scanID })).first)
        context.delete(record); try context.save()
        var enrollmentCalls = 0, releaseCalls = 0
        let continuation = CaptureCompletedHistoryContinuation(requireCurrent: {}, inspect: { candidate in
            try await fixture.owner.inspectCompletedAppCapture(candidate)
        }, enroll: { _ in enrollmentCalls += 1 }, release: { _ in releaseCalls += 1 })
        await #expect(throws: (any Error).self) { try await continuation.finish(candidate) }
        #expect(enrollmentCalls == 0 && releaseCalls == 0)
        #expect(try fixture.snapshot().release == nil)
        #expect(await fixture.owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func resumedReleaseRechecksDeletionCompletionAndFundingBeforeUnlink() async throws {
        let fixture = try await fixture(), plan = fixture.plan
        try await fixture.enroll()
        try fixture.owner.configureCaptureAcceptedReleaseForTesting { point in
            if point == .afterIntentSave { throw SharedMediaStorageFailure.unavailable }
        }
        await #expect(throws: (any Error).self) {
            _ = try await fixture.owner.releaseAppCaptureSubmission(scanID: plan.scanID, generation: plan.generation)
        }
        try fixture.owner.configureCaptureAcceptedReleaseForTesting(nil)
        let retainedFiles = try FileManager.default.contentsOfDirectory(atPath: fixture.store.directory.path).sorted()
        #expect(!retainedFiles.isEmpty)
        let context = ModelContext(fixture.store.container); context.autosaveEnabled = false
        let job = try #require(try context.fetchOfflineJob(id: OfflineQueueManager.scanIngestionJobId(scanId: plan.scanID.uuidString.lowercased())))
        let metadata = try #require(job.metadataJSON)
        let funding = try SharedMediaCaptureFundingReceipt.read(metadata)
        var pending = funding; pending.delivered = false
        job.metadataJSON = try pending.retaining(in: metadata, replacing: funding); try context.save()
        await #expect(throws: (any Error).self) {
            _ = try await fixture.owner.releaseAppCaptureSubmission(scanID: plan.scanID, generation: plan.generation)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.store.directory.path).sorted() == retainedFiles)
        job.metadataJSON = metadata; job.status = .running; try context.save()
        await #expect(throws: (any Error).self) {
            _ = try await fixture.owner.releaseAppCaptureSubmission(scanID: plan.scanID, generation: plan.generation)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.store.directory.path).sorted() == retainedFiles)
        job.status = .complete
        let deletion = PendingCloudDeletionTask(scanId: plan.scanID.uuidString.lowercased())
        context.insert(deletion); try context.save()
        await #expect(throws: (any Error).self) {
            _ = try await fixture.owner.releaseAppCaptureSubmission(scanID: plan.scanID, generation: plan.generation)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.store.directory.path).sorted() == retainedFiles)
        // Restore the fixture only. Production deletion uses separate erasure
        // authority; a success-release call never clears a deletion fence.
        context.delete(deletion); try context.save()
        let accepted = try fixture.snapshot()
        let source = try #require(accepted.artifacts.first(where: { $0.request.role == .sourceAudio }))
        // Accepted artifacts cannot mint a pre-submission source capability.
        #expect(throws: (any Error).self) {
            _ = try SharedMediaCaptureDraftSourceInput(retained: source.request)
        }
        #expect(try await fixture.owner.releaseAppCaptureSubmission(scanID: plan.scanID, generation: plan.generation).releasedRevision != nil)
        #expect(await fixture.owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func missingHistoryAndChangedFundingCannotReleaseAndLaterSelectionIsPreserved() async throws {
        let fixture = try await fixture(), plan = fixture.plan
        await #expect(throws: (any Error).self) { _ = try await fixture.owner.releaseAppCaptureSubmission(scanID: plan.scanID, generation: plan.generation) }
        #expect(try fixture.snapshot().release == nil)
        try await fixture.enroll()
        try await SharedMediaCaptureResultWriterTests().verifyAcknowledgedContinuation(plan: plan, analysis: fixture.analysis,
            container: fixture.store.container, cloud: fixture.cloud)
        let context = ModelContext(fixture.store.container); context.autosaveEnabled = false
        let scan = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        let selected = scan.selectedAnalysisID, notes = scan.fieldNotes
        let job = try #require(try context.fetchOfflineJob(id: OfflineQueueManager.scanIngestionJobId(scanId: scan.id)))
        let metadata = try #require(job.metadataJSON), funding = try SharedMediaCaptureFundingReceipt.read(metadata)
        var pending = funding; pending.delivered = false
        job.metadataJSON = try pending.retaining(in: metadata, replacing: funding); try context.save()
        await #expect(throws: (any Error).self) { _ = try await fixture.owner.releaseAppCaptureSubmission(scanID: plan.scanID, generation: plan.generation) }
        #expect(try fixture.snapshot().release == nil)
        job.metadataJSON = metadata; try context.save()
        _ = try await fixture.owner.releaseAppCaptureSubmission(scanID: plan.scanID, generation: plan.generation)
        let after = try #require(ModelContext(fixture.store.container).fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(after.selectedAnalysisID == selected && selected != fixture.analysis && after.fieldNotes == notes)
        #expect(await fixture.owner.invalidateAndAwaitForAccountTransition())
    }
}
