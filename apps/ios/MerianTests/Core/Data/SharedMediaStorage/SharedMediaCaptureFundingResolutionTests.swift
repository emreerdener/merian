import Foundation
@testable import Merian
import Testing

@Suite("Capture deferred funding identity")
@MainActor
struct SharedMediaCaptureFundingResolutionTests {
    private func fixture() throws -> SharedMediaCaptureSubmission {
        let owner = UUID()
        let plan = try CaptureInitialEvidencePlan(ownerID: owner, scanID: UUID(), generation: UUID(), items: [
            .audio(.init(source: .init(mediaID: UUID(), contentType: "audio/wav", byteCount: 48,
                sha256: String(repeating: "a", count: 64)), preparedMediaID: UUID()))])
        let baseline = try SharedMediaCaptureSubmissionContextTests.context(plan)
        let context = try SharedMediaCaptureSubmissionContext(plan: plan,
            funding: .init(accountId: owner, scanId: plan.scanID.uuidString, source: .deferredFlash,
                blockerScanIds: [UUID().uuidString], createdAt: baseline.timestamp), timestamp: baseline.timestamp,
            telemetry: baseline.telemetry, blurScore: nil, preferredGoal: nil)
        let profile = SharedMediaNativeAppProfile(ownerID: owner, inventoryID: UUID(), generation: UUID(),
            storeIdentity: UUID().uuidString, physicalBinding: String(repeating: "a", count: 64),
            receiptDigest: String(repeating: "b", count: 64), physicalBindingFormat: .physicalRootsV1)
        return try .init(plan: plan, context: context, profile: profile, writerEpoch: UUID(), inventoryRevision: 4,
            rootBindingSHA256: String(repeating: "c", count: 64), eventID: UUID(), artifactIDs: plan.uploads.map { _ in UUID() })
    }

    private func resolve(_ submission: SharedMediaCaptureSubmission) throws -> SharedMediaCaptureFundingResolution {
        var effective = try submission.context.metadata(plan: submission.plan()).funding
        effective.source = .immediateFlash; effective.blockerScanIds = []
        return try .init(submission: submission, effective: effective, evidenceSHA256: String(repeating: "d", count: 64))
    }

    @Test func resolutionSurvivesEncodingAndDispatchWithoutChangingOriginalContext() throws {
        let original = try fixture(), frozenBytes = try original.encoded(), resolution = try resolve(original)
        #expect(try !SharedMediaCaptureFundingResolution.funding(original.context.jobMetadataJSON, submission: original).allowsDispatch)
        let saved = try resolution.retaining(in: original.context.jobMetadataJSON, submission: original)
        let cold = try SharedMediaCaptureSubmission.decode(frozenBytes, sha256: SharedMediaAcquisitionEncoding.digest(frozenBytes))
        #expect(try SharedMediaCaptureFundingResolution.read(saved, submission: cold) == resolution)
        #expect(try SharedMediaCaptureFundingResolution.funding(saved, submission: cold).allowsDispatch)
        #expect(try resolution.retaining(in: saved, submission: cold) == saved)
        let dispatched = try SharedMediaCaptureExecutionIntent.reserving(submission: cold, attemptCount: 1, metadata: saved)
        #expect(try SharedMediaCaptureExecutionIntent.read(dispatched, submission: cold)?.fundingResolutionSHA256 == resolution.digest)
        #expect(try SharedMediaCaptureFundingResolution.read(dispatched, submission: cold) == resolution)
        #expect(try cold.encoded() == frozenBytes)
        #expect(throws: (any Error).self) { try resolution.retaining(in: dispatched, submission: cold) }
    }

    @Test func changedFundingMissingResolutionAndDifferentObservationAreRejected() throws {
        let original = try fixture(), resolution = try resolve(original)
        let saved = try resolution.retaining(in: original.context.jobMetadataJSON, submission: original)
        let withoutProof = try #require(OfflineScanJobMetadataContract.settingFunding(resolution.effective,
            in: original.context.jobMetadataJSON))
        #expect(throws: (any Error).self) { try SharedMediaCaptureFundingResolution.funding(withoutProof, submission: original) }
        #expect(throws: (any Error).self) { try SharedMediaCaptureExecutionIntent.read(withoutProof, submission: original) }
        let different = try fixture()
        #expect(throws: (any Error).self) { try SharedMediaCaptureFundingResolution.read(saved, submission: different) }
        var changed = resolution.effective; changed.source = .paidPro
        let contender = try SharedMediaCaptureFundingResolution(submission: original, effective: changed,
            evidenceSHA256: String(repeating: "e", count: 64))
        #expect(throws: (any Error).self) { try contender.retaining(in: saved, submission: original) }
    }

    @Test func terminalSettlementMustRetainResolutionAssociation() throws {
        let original = try fixture(), resolution = try resolve(original)
        let saved = try resolution.retaining(in: original.context.jobMetadataJSON, submission: original)
        let dispatched = try SharedMediaCaptureExecutionIntent.reserving(submission: original, attemptCount: 1, metadata: saved)
        let good = try SharedMediaCaptureFundingReceipt(scanID: original.scanID, settlement: nil, resolutionSHA256: resolution.digest)
        let retained = try good.retaining(in: dispatched)
        try SharedMediaCaptureFundingResolution.requireOperationalCustody(retained, submission: original)
        let wrong = try SharedMediaCaptureFundingReceipt(scanID: original.scanID, settlement: nil)
        #expect(throws: (any Error).self) {
            try SharedMediaCaptureFundingResolution.requireOperationalCustody(wrong.retaining(in: dispatched), submission: original)
        }
        #expect(throws: (any Error).self) {
            try SharedMediaCaptureFundingResolution.requireOperationalCustody(good.retaining(in: saved), submission: original)
        }
    }

    @Test func unknownOrUnprovenBlockerCannotReleaseDeferredFunding() throws {
        let original = try fixture()
        var funding = try original.context.metadata(plan: original.plan()).funding
        let second = UUID().uuidString.lowercased()
        funding.blockerScanIds.append(second)
        let first = try #require(funding.blockerScanIds.first)
        let proofs = Dictionary(uniqueKeysWithValues: (funding.blockerScanIds + [funding.scanId]).map {
            ($0, String(repeating: "f", count: 64))
        })
        func evidence(_ states: [String: String], proofs: [String: String]) -> CaptureDeferredFundingDecision.Evidence {
            .init(ownerID: funding.accountId, sessionGeneration: UUID(), entitlementVersion: 3,
                paidAvailable: false, complimentaryAvailable: true, availableCredits: 1,
                blockerStates: states, unresolvedBlockers: [], ownershipProofs: proofs)
        }
        #expect(CaptureDeferredFundingDecision(original: funding,
            evidence: evidence([first: "released"], proofs: proofs)) == nil)
        #expect(CaptureDeferredFundingDecision(original: funding,
            evidence: evidence([first: "released", second: "held"], proofs: [:])) == nil)
        let decision = try #require(CaptureDeferredFundingDecision(original: funding,
            evidence: evidence([first: "released", second: "held"], proofs: proofs)))
        #expect(decision.effective.source == .complimentaryPro)
        #expect(decision.original == funding && decision.effective.createdAt == funding.createdAt)
        #expect(decision.effective.blockerScanIds.isEmpty)
    }
}
