import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite("Accepted Capture admission funding", .serialized, .sharedProcessState(.offlineQueueManager))
struct SharedMediaCaptureAdmissionFundingTests {
    typealias Store = SharedMediaCaptureArtifactWriterTests.Store
    struct Prepared {
        let plan: CaptureInitialEvidencePlan
        let context: SharedMediaCaptureSubmissionContext
        let blocker: String
    }

    @Test(arguments: [false, true])
    func deferredAcceptanceMetersOnceAndResolutionSurvivesLostSaveAcknowledgement(paid: Bool) async throws {
        let store = try await Store(), owner = try await store.open()
        let manager = EntitlementManager.shared, usage = UsageManager.shared
        manager.resetForTesting(userID: store.base.ownerID)
        let oldOverride = UsageManager.debugFreeScanLimitOverride
        UsageManager.debugFreeScanLimitOverride = false
        let scanID = store.input.scanID.uuidString.lowercased()
        defer {
            usage.refundScan(scanId: scanID)
            UsageManager.debugFreeScanLimitOverride = oldOverride
            manager.resetForTesting()
        }
        let prepared = try await prepare(store, owner: owner)
        let plan = prepared.plan, frozen = prepared.context, blocker = prepared.blocker
        let before = usage.freeScansRemaining
        try await owner.restoreCaptureAdmissionFunding()
        let once = usage.freeScansRemaining
        try await owner.restoreCaptureAdmissionFunding()
        #expect(usage.freeScansRemaining == once && once == max(0, before - 1))
        let page = try await owner.captureExecutionRecoveryPage()
        let pending = try #require(page.candidates.first)
        #expect(pending.attemptCount == 0 && pending.status == .pending && pending.dispatch == nil)
        let original = try await owner.capturePreparationFunding(pending)
        #expect(original.source == .deferredFlash)
        let entries = try await owner.captureFundingOwnership(original)
        manager.applyComplimentaryState(.held, scanId: blocker, terminalized: false)
        if paid {
            let bytes = try JSONSerialization.data(withJSONObject: [
                "current_plan": "pro_paid", "current_tier": "pro", "is_paid": true,
                "scans_remaining": 3, "scans_available_to_start": 3,
                "in_flight_count": 0, "entitlement_version": 1
            ])
            let snapshot = try JSONDecoder().decode(EntitlementSnapshotDTO.self, from: bytes)
            #expect(manager.apply(snapshot, for: store.base.ownerID))
        }
        let evidence = try #require(manager.captureFundingEvidence(ownershipProofs: entries.mapValues(\.proof)))
        let decision = try #require(CaptureDeferredFundingDecision(original: original, evidence: evidence))
        #expect(decision.effective.source == (paid ? .paidPro : .immediateFlash))
        try owner.configureCaptureSubmissionWritingForTesting { if $0 == .afterSave { throw SharedMediaStorageFailure.unavailable } }
        await #expect(throws: (any Error).self) {
            try await owner.resolveCaptureFunding(pending, decision: decision, requireEvidence: {})
        }
        let closed = await owner.invalidateAndAwaitForAccountTransition()
        #expect(closed)
        let cold = try await store.open(); try await cold.resumeAppCaptureRoot()
        let serverPlan = manager.currentPlan, serverVersion = manager.entitlementVersion
        let serverRemaining = manager.scansRemaining, serverAvailable = manager.scansAvailableToStart
        try await cold.restoreCaptureAdmissionFunding()
        try await cold.restoreCaptureAdmissionFunding()
        let recovered = try await cold.captureExecutionRecoveryPage()
        let candidate = try #require(recovered.candidates.first)
        let effective = try await cold.capturePreparationFunding(candidate)
        #expect(effective == decision.effective && candidate.attemptCount == 0)
        #expect(usage.freeScansRemaining == (paid ? before : once))
        #expect(manager.currentPlan == serverPlan && manager.entitlementVersion == serverVersion)
        #expect(manager.scansRemaining == serverRemaining && manager.scansAvailableToStart == serverAvailable)
        let context = ModelContext(store.container); context.autosaveEnabled = false
        let saved = try #require(try SharedMediaCaptureSubmissionReceipt.matching(scanID: plan.scanID,
            generation: plan.generation, in: context))
        #expect(saved.submission.context == frozen)
        let job = try #require(try context.fetchOfflineJob(id: saved.submission.jobID))
        let raw = try #require(job.metadataJSON)
        #expect(try SharedMediaCaptureFundingResolution.read(raw, submission: saved.submission)?.effective == decision.effective)
        let coldClosed = await cold.invalidateAndAwaitForAccountTransition()
        #expect(coldClosed)
    }

    @Test func changedBlockerCustodyRejectsResolutionBeforeSave() async throws {
        let store = try await Store(), owner = try await store.open()
        let manager = EntitlementManager.shared
        manager.resetForTesting(userID: store.base.ownerID)
        defer { manager.resetForTesting() }
        let prepared = try await prepare(store, owner: owner), blocker = prepared.blocker
        let page = try await owner.captureExecutionRecoveryPage(), pending = try #require(page.candidates.first)
        let funding = try await owner.capturePreparationFunding(pending)
        let entries = try await owner.captureFundingOwnership(funding)
        manager.applyComplimentaryState(.held, scanId: blocker, terminalized: false)
        let evidence = try #require(manager.captureFundingEvidence(ownershipProofs: entries.mapValues(\.proof)))
        let decision = try #require(CaptureDeferredFundingDecision(original: funding, evidence: evidence))
        let context = ModelContext(store.container); context.autosaveEnabled = false
        let job = try #require(try context.fetchOfflineJob(id: OfflineQueueManager.scanIngestionJobId(scanId: blocker)))
        job.status = .waiting; try context.save()
        await #expect(throws: (any Error).self) {
            try await owner.resolveCaptureFunding(pending, decision: decision, requireEvidence: {})
        }
        let fresh = ModelContext(store.container); fresh.autosaveEnabled = false
        let target = try #require(try fresh.fetchOfflineJob(id: OfflineQueueManager.scanIngestionJobId(scanId: funding.scanId)))
        #expect(OfflineScanJobMetadataContract.object(from: target.metadataJSON)[SharedMediaCaptureFundingResolution.key] == nil)
        let closed = await owner.invalidateAndAwaitForAccountTransition()
        #expect(closed)
    }

    private func prepare(_ store: Store, owner: SharedMediaNativeOriginalOwner) async throws
        -> Prepared {
        let blocker = UUID().uuidString.lowercased()
        let plan = try CaptureInitialEvidencePlan(ownerID: store.base.ownerID, scanID: store.input.scanID,
            generation: store.input.submissionGeneration, items: [.audio(.init(source: .init(mediaID: UUID(),
                contentType: "audio/wav", byteCount: store.bytes.count, sha256: SharedMediaAcquisitionEncoding.digest(store.bytes)),
                preparedMediaID: UUID()))])
        let base = try SharedMediaCaptureSubmissionContextTests.context(plan)
        let frozen = try SharedMediaCaptureSubmissionContext(plan: plan,
            funding: .init(accountId: plan.ownerID, scanId: plan.scanID.uuidString, source: .deferredFlash,
                blockerScanIds: [blocker], createdAt: base.timestamp), timestamp: base.timestamp,
            telemetry: base.telemetry, blurScore: nil, preferredGoal: nil)
        try await owner.resumeAppCaptureRoot()
        let bytes = store.bytes
        _ = try await owner.acceptAppCaptureDraft(plan: plan, context: frozen) { _ in bytes }
        let context = ModelContext(store.container); context.autosaveEnabled = false
        context.insert(OfflineJobRecord(id: OfflineQueueManager.scanIngestionJobId(scanId: blocker),
            kind: .scanIngestion, subjectId: blocker, metadataJSON: "{}"))
        try context.save()
        return .init(plan: plan, context: frozen, blocker: blocker)
    }
}
