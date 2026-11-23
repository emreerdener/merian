import Foundation
@testable import Merian
import SwiftData
import Testing

@Suite("Capture submission scoped audit", .serialized)
@MainActor
struct SharedMediaCaptureSubmissionAuditTests {
    typealias Store = SharedMediaCaptureArtifactFilesTests.Store

    @Test(arguments: ["missing", "reserved", "writing", "ready", "accepted"])
    func wholePlanRequiresLiveRootAndChargesEachLiabilityOnce(_ phase: String) async throws {
        let store = try Store(capturePlan: true), context = store.ledger.context
        let submission = try #require(store.submission), profile = submission.profile
        let row = try #require(try context.fetch(FetchDescriptor<SharedMediaOrdinarySubmissionRecord>()).first)
        if phase == "missing" {
            context.delete(store.ledger.row); context.delete(store.ledger.allocation)
            context.delete(store.ledger.reference); context.delete(store.ledger.lease)
            try context.save()
        } else if phase == "writing" { _ = try store.begin() } else if phase == "ready" || phase == "accepted" {
            _ = try store.finish()
        }
        if phase == "accepted" {
            let receipt = try SharedMediaCaptureSubmissionReceipt.read(row, in: context)
            let acceptance = try SharedMediaCaptureSubmissionAcceptance(submission: submission,
                artifacts: receipt.artifacts, inventoryRevision: 8)
            let data = try acceptance.encoded(submission: submission, artifacts: receipt.artifacts)
            row.phaseRaw = "accepted"; row.revision = 1; row.acceptanceData = data
            row.acceptanceSHA256 = SharedMediaAcquisitionEncoding.digest(data)
            store.ledger.inventory.revision = 8; try context.save()
        }
        #expect(throws: (any Error).self) { try SharedMediaOrdinaryStoreAudit.verify(context: context, profile: profile) }
        let parent = try SharedMediaCaptureSubmissionReceipt.read(row, in: context), physical = try await store.audit()
        try await SharedMediaCaptureArtifactInspection.withVerified(container: store.ledger.container,
            profile: profile, files: store.files, checkpoint: {}) { capture in
                try await SharedMediaOrdinaryInspection.withVerifiedCapture(container: store.ledger.container,
                    profile: profile, capture: capture, checkpoint: {}) { ordinary in
                        #expect(ordinary.snapshot.submissions == 1 && ordinary.snapshot.holds == 0)
                        #expect(ordinary.snapshot.metadataBytes == parent.metadataBytes)
                        #expect(ordinary.snapshot.reservedBytes == parent.reservedBytes)
                        let result = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: context,
                            inventory: store.ledger.inventory, ownerID: profile.ownerID, format: .appV2, ordinary: ordinary)
                        var expected = SharedMediaStoragePolicy.Totals()
                        try expected.includePhotoPhysical(materialized: physical.ledger.materializedBytes + physical.ledger.metadataBytes,
                            reserved: physical.ledger.reservedBytes + physical.ledger.futureMetadataReservationBytes)
                        try expected.includePhotoPhysical(materialized: parent.metadataBytes, reserved: parent.reservedBytes)
                        if phase != "accepted" {
                            try expected.includePhotoPackage(id: submission.scanID, bytes: submission.packageBytes)
                            #expect(ordinary.snapshot.capturePackages.count == 1)
                        } else { #expect(ordinary.snapshot.capturePackages.isEmpty) }
                        #expect(result.totals == expected)
                        if phase == "missing" { #expect(parent.reservedBytes > store.bytes.count) }
                    }
            }
    }

    @Test func emptyReservationsStillEnforceThePendingObservationLimit() async throws {
        let store = try Store(capturePlan: true), context = store.ledger.context
        let original = try #require(store.submission), profile = original.profile
        context.delete(store.ledger.row); context.delete(store.ledger.allocation)
        context.delete(store.ledger.reference); context.delete(store.ledger.lease)
        try context.save()
        for count in 2...5 {
            let plan = try CaptureInitialEvidencePlan(ownerID: profile.ownerID, scanID: UUID(), generation: UUID(),
                items: [.audio(.init(source: .init(mediaID: UUID(), contentType: "audio/wav", byteCount: 48,
                    sha256: SharedMediaAcquisitionEncoding.digest(store.bytes)), preparedMediaID: UUID()))])
            let parent = try SharedMediaCaptureSubmission(plan: plan, context: SharedMediaCaptureSubmissionContextTests.context(plan), profile: profile, writerEpoch: UUID(),
                inventoryRevision: store.ledger.inventory.revision, rootBindingSHA256: original.rootBindingSHA256,
                eventID: UUID(), artifactIDs: [UUID()])
            let data = try parent.encoded()
            context.insert(SharedMediaOrdinarySubmissionRecord(inventoryID: profile.inventoryID,
                inventoryGeneration: profile.generation, ownerID: profile.ownerID, recipientScanID: parent.scanID,
                submissionGeneration: parent.generation, jobID: parent.jobID, eventID: parent.eventID,
                writerEpoch: parent.writerEpoch, formatRaw: parent.format.rawValue, requestData: data,
                requestSHA256: SharedMediaAcquisitionEncoding.digest(data), observationSHA256: parent.observation.sha256))
            store.ledger.inventory.revision += 1; try context.save()
            if count <= 4 {
                try await SharedMediaCaptureArtifactInspection.withVerified(container: store.ledger.container,
                    profile: profile, files: store.files, checkpoint: {}) { capture in
                        let audit = try SharedMediaOrdinaryStoreAudit.verify(context: context, profile: profile, capture: capture)
                        #expect(audit.capturePackages.count == count)
                    }
            } else {
                await #expect(throws: SharedMediaStorageFailure.capacity) {
                    try await SharedMediaCaptureArtifactInspection.withVerified(container: store.ledger.container,
                        profile: profile, files: store.files, checkpoint: {}) { capture in
                            try SharedMediaOrdinaryStoreAudit.verify(context: context, profile: profile, capture: capture)
                        }
                }
            }
        }
    }

    @Test func canonicalParentDoesNotPermitUnlistedArtifacts() async throws {
        let store = try Store(capturePlan: true), context = store.ledger.context
        let original = try #require(store.submission), plan = try original.plan()
        let replacement = try SharedMediaCaptureSubmission(plan: plan, context: SharedMediaCaptureSubmissionContextTests.context(plan), profile: original.profile,
            writerEpoch: original.writerEpoch, inventoryRevision: original.inventoryRevision,
            rootBindingSHA256: original.rootBindingSHA256, eventID: original.eventID, artifactIDs: [UUID()])
        let row = try #require(try context.fetch(FetchDescriptor<SharedMediaOrdinarySubmissionRecord>()).first)
        row.requestData = try replacement.encoded()
        row.requestSHA256 = SharedMediaAcquisitionEncoding.digest(try replacement.encoded()); try context.save()
        await #expect(throws: (any Error).self) {
            try await SharedMediaCaptureArtifactInspection.withVerified(container: store.ledger.container,
                profile: original.profile, files: store.files, checkpoint: {}) { capture in
                    try SharedMediaOrdinaryStoreAudit.verify(context: context, profile: original.profile, capture: capture)
                }
        }
    }
}
