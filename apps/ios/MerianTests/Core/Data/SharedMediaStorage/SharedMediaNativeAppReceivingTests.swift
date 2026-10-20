import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Atomic inactive native photo receiving", .serialized)
@MainActor
struct SharedMediaNativeAppReceivingTests {
    typealias Store = SharedMediaNativeAppMetadataTests.Store
    private static let recipe = SharedMediaNativePreparationRecipe(format: .stillImage, isPro: false,
        cropDisplaySize: nil, quarterTurns: 0, scale: 1, offsetX: 0, offsetY: 0)

    @Test(arguments: [1, 2])
    func completeSetAndColdExactRecoveryNeverSaveTwice(_ count: Int) async throws {
        let (h, owner, r) = try await fixture(count: count)
        var saves = 0
        try owner.setMetadataFault { if $0 == .beforeSave { saves += 1 } }
        #expect(try await owner.receiveAppPhotos(r) == r.cohort)
        #expect(try await owner.receiveAppPhotos(r) == r.cohort)
        #expect(saves == 1)
        try verify(h, r)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await reopen(h)
        try cold.setMetadataFault { if $0 == .beforeSave { throw SharedMediaStorageFailure.closed } }
        #expect(try await cold.receiveAppPhotos(r) == r.cohort)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test func laterUnrelatedAcquisitionDoesNotInvalidateExactRecovery() async throws {
        let (h, owner, r) = try await fixture()
        _ = try await owner.receiveAppPhotos(r)
        let other = UUID(), draft = UUID()
        let acquisition = try await owner.prepareAppOriginal(packageID: other, draftGeneration: draft, ordinal: 0, kind: .picker)
        let bytes = PhotoPreparationTestHarness.image()
        _ = try await owner.acquireAppOriginal(acquisition) { bytes }
        let before = try h.package(other).supportingContextData
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await reopen(h)
        try cold.setMetadataFault { if $0 == .beforeSave { throw SharedMediaStorageFailure.closed } }
        #expect(try await cold.receiveAppPhotos(r) == r.cohort)
        #expect(try h.package(other).supportingContextData == before)
        try verify(h, r)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["before", "after", "readback"])
    func acknowledgementFaultNeverCreatesHalfASetOrRepeatsSave(_ fault: String) async throws {
        let (h, owner, r) = try await fixture()
        var saves = 0, saved = false
        try owner.setMetadataFault {
            if $0 == .beforeSave { saves += 1; if fault == "before" { throw SharedMediaStorageFailure.unavailable } }
            if $0 == .afterSave { saved = true; if fault == "after" { throw SharedMediaStorageFailure.unavailable } }
            if $0 == .beforeReadback && saved && fault == "readback" { throw SharedMediaStorageFailure.unavailable }
        }
        if fault == "after" { #expect(try await owner.receiveAppPhotos(r) == r.cohort) }
        else { await #expect(throws: (any Error).self) { _ = try await owner.receiveAppPhotos(r) } }
        #expect(saves == 1)
        if fault == "before" { try unchanged(h, r) } else { try verify(h, r) }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        if fault != "before" {
            let cold = try await reopen(h)
            try cold.setMetadataFault { if $0 == .beforeSave { throw SharedMediaStorageFailure.closed } }
            #expect(try await cold.receiveAppPhotos(r) == r.cohort)
            #expect(await cold.invalidateAndAwaitForAccountTransition())
        }
    }

    @Test(arguments: ["consumer", "queue", "job", "event", "queueMetadata", "jobMetadata", "eventMetadata", "consumerIdentity"])
    func partialOrChangedSavedSetCannotRecoverOrRemint(_ fault: String) async throws {
        let (h, owner, r) = try await fixture()
        _ = try await owner.receiveAppPhotos(r)
        let c = h.context(), rows = try #require(try SharedMediaNativeReceivingRows.read(r, in: c, absent: false))
        switch fault {
        case "consumer": c.delete(rows.consumer)
        case "queue": c.delete(rows.queue)
        case "job": c.delete(rows.job)
        case "event": c.delete(rows.event)
        case "queueMetadata": rows.queue.fieldNotes = "unexpected"
        case "jobMetadata": rows.job.metadataJSON = "{}"
        case "eventMetadata": rows.event.metadataJSON = "{}"
        default: rows.consumer.observationID = UUID().uuidString.lowercased()
        }
        try c.save()
        var saves = 0; try owner.setMetadataFault { if $0 == .beforeSave { saves += 1 } }
        await #expect(throws: (any Error).self) { _ = try await owner.receiveAppPhotos(r) }
        #expect(saves == 0)
        #expect(try h.package().supportingContextData == r.frozenPackage().envelope)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["queue", "observation", "job", "event"])
    func freshAliasesAndReverseJoinsBlockInsertion(_ fault: String) async throws {
        let (h, owner, r) = try await fixture()
        let c = h.context()
        switch fault {
        case "queue": c.insert(OfflineQueuedScan(id: r.cohort.originQueueID.uppercased()))
        case "observation": c.insert(OfflineQueuedScan(id: r.cohort.observationID.uppercased()))
        case "job": c.insert(OfflineJobRecord(id: "scan-ingestion:" + r.cohort.originQueueID.uppercased(), kind: .scanIngestion))
        default: c.insert(OfflineQueueEvent(id: r.eventID.uppercased(), kind: .queued))
        }
        try c.save()
        await #expect(throws: (any Error).self) { _ = try await owner.receiveAppPhotos(r) }
        #expect(try h.package().supportingContextData == r.package.envelope)
        #expect(try h.context().fetchCount(FetchDescriptor<SharedMediaConsumerRecord>()) == 0)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["original", "output", "member", "package", "inventory", "reference", "edge", "counter"])
    func finalSealsRejectChangedFilesAndDurableFacts(_ fault: String) async throws {
        let (h, owner, r) = try await fixture()
        var reached = false
        try owner.setMetadataFault { point in
            guard point == .beforeSave else { return }; reached = true
            if fault == "original" || fault == "output" {
                let cohort = try SharedMediaNativeFrozenCohort.decode(r.freeze.commit.cohort.bytes)
                let intent = try SharedMediaNativeDerivativeIntent.decode(#require(cohort.entries.first).intent.bytes)
                let assetID = intent.ai.assetID
                let output = try #require(try h.context().fetch(FetchDescriptor<PhotoPreparationAsset>(predicate: #Predicate { $0.id == assetID })).first)
                let token = fault == "original" ? intent.preparation.original.token : output.fileToken
                let path = h.parent.appendingPathComponent("photo/PhotoPreparation").appendingPathComponent(token)
                let bytes = try Data(contentsOf: path); try FileManager.default.removeItem(at: path); try bytes.write(to: path)
            } else {
                let c = h.context()
                if fault == "package" { try h.package(in: c).revision += 1 }
                else if fault == "inventory" { try #require(try c.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first).revision += 1 }
                else if fault == "member" { try #require(try c.fetch(FetchDescriptor<SharedMediaPendingMembershipRecord>()).first).revision += 1 }
                else {
                    let cohort = try SharedMediaNativeFrozenCohort.decode(r.freeze.commit.cohort.bytes)
                    let original = try SharedMediaNativeDerivativeIntent.decode(#require(cohort.entries.first).intent.bytes).preparation.original
                    let assetID = original.reference.assetID, referenceID = original.reference.referenceID
                    if fault == "counter" { try #require(try c.fetch(FetchDescriptor<SharedMediaAssetReferenceCountRecord>(predicate: #Predicate { $0.id == assetID })).first).liveCount += 1 }
                    else if fault == "edge" { try #require(try c.fetch(FetchDescriptor<SharedMediaReferenceRecord>(predicate: #Predicate { $0.id == referenceID })).first).revision += 1 }
                    else { try #require(try c.fetch(FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.id == referenceID })).first).revision += 1 }
                }
                try c.save()
            }
        }
        await #expect(throws: (any Error).self) { _ = try await owner.receiveAppPhotos(r) }
        #expect(reached); try unchanged(h, r, revision: fault == "package" ? 1 : 0)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func existingReceivingAndOrdinaryRowsArePreserved() async throws {
        let (h, owner, r) = try await fixture(receiving: true)
        let before = try h.context().fetch(FetchDescriptor<SharedMediaConsumerRecord>()).map { SharedMediaNativeAppMetadataFacts.Consumer($0) }
        let ordinaryID = UUID().uuidString, c = h.context()
        c.insert(OfflineQueuedScan(id: ordinaryID, fieldNotes: "keep ordinary draft")); try c.save()
        _ = try await owner.receiveAppPhotos(r)
        let after = try h.context().fetch(FetchDescriptor<SharedMediaConsumerRecord>()).filter { $0.id != r.cohort.bindingID }.map { SharedMediaNativeAppMetadataFacts.Consumer($0) }
        #expect(after == before)
        #expect(try h.context().fetch(FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == ordinaryID })).first?.fieldNotes == "keep ordinary draft")
        #expect(try h.package(h.ordinaryID).supportingContextData == Data("ordinary-draft".utf8))
        try verify(h, r); #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func queueAndMetadataIndependentlyDenyLegacyExecution() async throws {
        let (h, owner, r) = try await fixture(); _ = try await owner.receiveAppPhotos(r)
        let c = h.context(), rows = try #require(try SharedMediaNativeReceivingRows.read(r, in: c, absent: false))
        #expect(!rows.queue.permitsOrdinaryInference)
        #expect(!SharedMediaLegacyQueueAccess.permitsMetadata(rows.job.metadataJSON))
        #expect(try !SharedMediaLegacyQueueAccess.permits(c, scanID: r.cohort.originQueueID))
        #expect(throws: (any Error).self) {
            try SharedMediaLegacyQueueAccess.requireJobMutation(c, id: r.jobID, kind: .scanIngestion,
                subjectID: r.cohort.originQueueID, metadata: r.metadata, existing: rows.job)
        }
        rows.queue.mediaAuthorityRaw = "legacy"; #expect(!rows.queue.permitsOrdinaryInference)
        rows.queue.mediaAuthorityRaw = "sharedDirectNativeReceivingV1"; rows.queue.sharedMediaConsumerID = nil
        #expect(!rows.queue.permitsOrdinaryInference); c.rollback()
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func cancelledCoordinatorWaitReleasesLocksWithoutAdmission() async throws {
        let (h, owner, r) = try await fixture(), coordinator = ScanInferencePersistenceCoordinator.shared
        let held = await coordinator.acquireAll(scanIds: [r.cohort.originQueueID, r.cohort.observationID])
        let task = Task { try await owner.receiveAppPhotos(r) }
        let first = held[0]
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !(await coordinator.hasWaitingWriter(scanId: first)), ContinuousClock.now < deadline { await Task.yield() }
        let waiting = await coordinator.hasWaitingWriter(scanId: first)
        #expect(waiting)
        task.cancel(); await coordinator.releaseAll(scanIds: held)
        await #expect(throws: (any Error).self) { _ = try await task.value }
        try unchanged(h, r)
        // Reacquisition proves both locks were released, not just the first.
        #expect(try await owner.receiveAppPhotos(r) == r.cohort)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func invalidatedOwnerCannotAdmitSavedIntent() async throws {
        let (h, owner, r) = try await fixture()
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        await #expect(throws: (any Error).self) { _ = try await owner.receiveAppPhotos(r) }
        try unchanged(h, r)
    }

    private func fixture(count: Int = 1, receiving: Bool = false) async throws -> (Store, SharedMediaNativeOriginalOwner, SharedMediaNativeAppReceivingRequest) {
        let h = try Store(receiving: receiving)
        let owner = try await (receiving ? h.openWithReceivingConsumer().0 : h.open())
        let metadata = try await owner.prepareAppMetadata(packageID: h.packageID, draftGeneration: h.draft, contexts: [.init(freeText: "Exact submitted supporting description")])
        _ = try await owner.saveAppMetadata(metadata)
        var pairs: [UUID] = []
        for ordinal in 0..<count {
            let request = try await owner.prepareAppOriginal(packageID: h.packageID, draftGeneration: h.draft, ordinal: Int64(ordinal), kind: .picker)
            let data = PhotoPreparationTestHarness.image(), acquired = try await owner.acquireAppOriginal(request) { data }
            let original = PhotoOriginalReference(ownerID: h.ownerID, packageID: h.packageID, referenceID: request.referenceID,
                assetID: request.assetID, assetGeneration: request.assetGeneration, draftGeneration: h.draft, referenceRevision: acquired.referenceRevision)
            let ready = try await owner.prepareAndDeliverAppPhoto(original: original, recipe: Self.recipe)
            pairs.append(try ready.intent().pairID)
        }
        let request = try await owner.appReceivingRequest(packageID: h.packageID, pairIDs: pairs, operationID: UUID(),
            queueID: UUID(), observationID: UUID(), bindingID: UUID(), generation: UUID(), eventID: UUID(), timestamp: Date(timeIntervalSince1970: 1_700_000_000))
        return (h, owner, request)
    }
    private func verify(_ h: Store, _ r: SharedMediaNativeAppReceivingRequest) throws {
        let c = h.context(), rows = try #require(try SharedMediaNativeReceivingRows.read(r, in: c, absent: false))
        #expect(try SharedMediaNativeConsumerGraph.validateScoped(rows.consumer, context: c, format: .appV2) == r.cohort)
        let inventory = try #require(try c.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first)
        let budget = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: c, inventory: inventory, ownerID: h.ownerID, format: .appV2)
        let packageID = r.package.id
        let member = try SharedMediaNativePairPlanGraph.one(c, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == packageID }))
        #expect((budget.metadataByPackage[packageID] ?? 0) >= Int64(rows.consumer.cohortData.count))
        #expect(try h.package(packageID).supportingContextData == r.frozenPackage().envelope)
        #expect(member.membersData == r.member.bytes)
    }
    private func unchanged(_ h: Store, _ r: SharedMediaNativeAppReceivingRequest, revision: Int64 = 0) throws {
        #expect(try h.package().supportingContextData == r.package.envelope)
        #expect(try h.package().revision == r.package.revision + revision)
        #expect(try h.context().fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
        #expect(try h.context().fetchCount(FetchDescriptor<OfflineJobRecord>()) == 0)
        #expect(try h.context().fetchCount(FetchDescriptor<OfflineQueueEvent>()) == 0)
        #expect(try h.context().fetchCount(FetchDescriptor<SharedMediaConsumerRecord>()) == 0)
    }
    private func reopen(_ h: Store) async throws -> SharedMediaNativeOriginalOwner {
        let owner = try SharedMediaNativeOriginalOwner.appDispatch(account: PhotoOriginalPreparationOwner.syntheticAccount(ownerID: h.ownerID, runtime: h.runtime), drain: .init())
        _ = try await owner.openApp(container: h.container, parent: h.parent, inventoryID: h.inventoryID); return owner
    }
}
