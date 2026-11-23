import Foundation
@testable import Merian
import SwiftData
import Testing

@Suite("Atomic ordinary original acceptance", .serialized)
@MainActor
struct SharedMediaOrdinaryAcceptanceTests {
    typealias Store = SharedMediaNativeAppMetadataTests.Store
    struct Fixture {
        let store: Store
        let owner: SharedMediaNativeOriginalOwner
        let admission: SharedMediaOrdinaryQueueAdmission
        let holds: SharedMediaOrdinaryHoldCohort
    }

    @Test(arguments: [1, 2])
    func wholeObservationSurvivesColdAcknowledgementWithoutSecondSave(_ count: Int) async throws {
        let fixture = try await fixture(count: count)
        let before = try fixture.store.package().supportingContextData
        var saves = 0
        try fixture.owner.setLifecycleFault { if $0 == .beforeSave { saves += 1 } }
        let accepted = try await fixture.owner.acceptAppOrdinary(fixture.admission, holds: fixture.holds)
        #expect(try await fixture.owner.acceptAppOrdinary(fixture.admission, holds: fixture.holds) == accepted)
        #expect(saves == 1)
        try verify(fixture)
        #expect(try fixture.store.package().supportingContextData == before)
        #expect(await fixture.owner.invalidateAndAwaitForAccountTransition())
        let cold = try await SharedMediaNativeReceivingStagingTests().reopen(fixture.store)
        try cold.setLifecycleFault { if $0 == .beforeSave { throw SharedMediaStorageFailure.closed } }
        #expect(try await cold.acceptAppOrdinary(fixture.admission, holds: fixture.holds) == accepted)
        #expect(try await cold.inspectApp().pendingPackages == 1)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["before", "after", "readback"])
    func interruptionNeverPersistsHalfASetOrLosesClaimedFunding(_ point: String) async throws {
        let fixture = try await fixture(count: 2)
        var saved = false
        try fixture.owner.setLifecycleFault {
            if $0 == .beforeSave && point == "before" { throw SharedMediaStorageFailure.unavailable }
            if $0 == .afterSave { saved = true; if point == "after" { throw SharedMediaStorageFailure.unavailable } }
            if $0 == .beforeReadback && saved && point == "readback" { throw SharedMediaStorageFailure.unavailable }
        }
        if point == "after" { _ = try await fixture.owner.acceptAppOrdinary(fixture.admission, holds: fixture.holds) } else {
            await #expect(throws: (any Error).self) {
                _ = try await fixture.owner.acceptAppOrdinary(fixture.admission, holds: fixture.holds)
            }
        }
        if point == "before" {
            let context = fixture.store.context()
            #expect(try context.fetchCount(FetchDescriptor<SharedMediaOrdinarySubmissionRecord>()) == 0)
            #expect(try context.fetchCount(FetchDescriptor<SharedMediaOrdinaryTransferRecord>()) == 0)
            #expect(try context.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
            #expect(try context.fetchCount(FetchDescriptor<OfflineJobRecord>()) == 0)
        } else { try verify(fixture) }
        #expect(await fixture.owner.invalidateAndAwaitForAccountTransition())
        if point != "before" {
            let cold = try await SharedMediaNativeReceivingStagingTests().reopen(fixture.store)
            _ = try await cold.acceptAppOrdinary(fixture.admission, holds: fixture.holds)
            #expect(await cold.invalidateAndAwaitForAccountTransition())
        }
    }

    @Test(arguments: ["job", "event", "deletion", "counter", "envelope", "artifact"])
    func finalFenceRejectsConcurrentDriftWithoutAcceptance(_ kind: String) async throws {
        let fixture = try await fixture(count: 1)
        var changed = false
        try fixture.owner.setLifecycleFault { point in
            guard point == .beforeSave, !changed else { return }; changed = true
            let context = fixture.store.context(), scan = fixture.admission.submission.scanID.uuidString
            if kind == "job" {
                context.insert(OfflineJobRecord(id: "scan-ingestion:" + scan, kind: .scanIngestion, subjectId: "unrelated"))
            } else if kind == "event" {
                context.insert(OfflineQueueEvent(jobId: fixture.admission.submission.jobID, scanId: scan,
                    kind: .failed, message: "Synthetic collision"))
            } else if kind == "deletion" {
                context.insert(PendingCloudDeletionTask(scanId: scan))
            } else if kind == "counter" {
                let row = try #require(try context.fetch(FetchDescriptor<SharedMediaAssetReferenceCountRecord>()).first)
                row.liveCount += 1
            } else if kind == "artifact" {
                context.insert(SharedMediaOrdinaryArtifactRecord(id: UUID(), inventoryID: UUID(), inventoryGeneration: UUID(),
                    ownerID: fixture.store.ownerID, recipientScanID: fixture.admission.submission.scanID,
                    submissionGeneration: UUID(), mediaID: UUID(), itemIndex: 0, roleRaw: "unknown", frameIndex: nil,
                    allocationID: UUID(), referenceID: UUID(), leaseID: UUID(), writerEpoch: UUID(),
                    requestData: Data(), requestSHA256: "synthetic"))
            } else {
                try fixture.store.package(in: context).supportingContextData = Data()
            }
            try context.save()
        }
        await #expect(throws: (any Error).self) {
            _ = try await fixture.owner.acceptAppOrdinary(fixture.admission, holds: fixture.holds)
        }
        #expect(changed)
        #expect(try fixture.store.context().fetchCount(FetchDescriptor<SharedMediaOrdinarySubmissionRecord>()) == 0)
        #expect(try fixture.store.context().fetchCount(FetchDescriptor<SharedMediaOrdinaryTransferRecord>()) == 0)
        #expect(await fixture.owner.invalidateAndAwaitForAccountTransition())
    }

    private func fixture(count: Int) async throws -> Fixture {
        let (store, owner, receiving) = try await SharedMediaNativeAppReceivingTests().fixture(count: count)
        let scan = UUID(), generation = UUID(), event = UUID()
        let binding = try await owner.appOriginalLifecycle {
            try $0.describeOrdinaryPhotoHolds(submission: receiving.freeze.commit.cohort,
                holdIDs: (0..<count).map { _ in UUID() }, scanID: scan, submissionGeneration: generation, eventID: event)
        }
        let submission = try SharedMediaOrdinarySubmission(binding: binding)
        let telemetry = CaptureTelemetry(subjectDistanceInMeters: nil, gpsLatitude: nil, gpsLongitude: nil,
            gpsElevation: nil, locationName: nil, weatherCondition: nil, weatherTemperatureF: nil,
            timeOfDay: nil, timestamp: nil, estimatedSizeCm: nil)
        let funding = ScanFundingReservation(accountId: store.ownerID, scanId: scan.uuidString,
            source: .deferredFlash, blockerScanIds: [], createdAt: Date(timeIntervalSince1970: 1))
        return try .init(store: store, owner: owner, admission: .init(submission: submission, funding: funding,
            timestamp: Date(timeIntervalSince1970: 2), telemetry: telemetry, blurScore: nil, preferredGoal: nil),
            holds: .init(binding.orderedRequests))
    }

    private func verify(_ fixture: Fixture) throws {
        let context = fixture.store.context()
        try fixture.admission.requireSaved(in: context)
        let receipt = try #require(try SharedMediaOrdinarySubmissionReceipt.existing(fixture.admission.submission, in: context))
        #expect(receipt.holds == fixture.holds)
        #expect(receipt.state == .accepted(try .init(submission: fixture.admission.submission, holds: fixture.holds)))
        #expect(try context.fetchCount(FetchDescriptor<SharedMediaOrdinaryTransferRecord>()) == fixture.holds.requests.count)
        #expect(try context.fetch(FetchDescriptor<OfflineQueuedScan>()).allSatisfy { !$0.permitsOrdinaryInference })
        for request in fixture.holds.requests {
            let original = try SharedMediaNativeOriginalAccounting.auditAcceptedOrdinary(assetID: request.source.assetID,
                inventoryID: request.profile.inventoryID, context: context)
            #expect(original.liveCount == request.liveCount + 1 && original.countRevision == request.countRevision + 1)
        }
    }
}
