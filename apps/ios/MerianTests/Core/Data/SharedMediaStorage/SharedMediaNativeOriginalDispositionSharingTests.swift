import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Inactive shared original disposition", .serialized)
@MainActor
struct SharedMediaNativeOriginalDispositionSharingTests {
    typealias Store = SharedMediaNativeAppMetadataTests.Store
    typealias Values = SharedMediaNativeReceivingReleaseValues
    typealias Rows = SharedMediaNativeAppOriginalRows
    let prior = SharedMediaNativeReleasePairOwnerTests()
    let base = SharedMediaNativeOriginalDispositionOwnerTests()
    static let recipe = SharedMediaNativePreparationRecipe(format: .stillImage, isPro: false,
        cropDisplaySize: nil, quarterTurns: 0, scale: 1, offsetX: 0, offsetY: 0)

    @Test(arguments: [false, true])
    func sharedRemovalPreservesSurvivorAndSinglePhysicalLiability(_ foreign: Bool) async throws {
        let (h, owner, before) = try await fixture(foreign: foreign)
        let target = before.plan.targets[0], old = try prior.snapshot(h)
        let oldAccounting = try base.accounting(h, target.original.assetID)
        let oldLiability = try SharedMediaNativeOriginalLiability.read(context: h.context(), inventoryID: h.inventoryID)
        let oldProjection = try SharedMediaNativeReleaseSurvivorProjection.maximum(old)
        let bytes = try base.originalBytes(h, before)
        var saves = 0
        try owner.setMetadataFault { if $0 == .beforeSave { saves += 1 } }
        let after = try await owner.disposeAppReleaseOriginal(before)
        #expect(after.targets[0].stage == .removed && after.targets[0].original?.disposition == .shared)
        #expect(after.targets[0].pair == before.targets[0].pair && after.plan == before.plan)
        #expect(after.targets[0].original?.retirementID == nil)
        let now = try base.accounting(h, target.original.assetID)
        #expect(now.liveCount == oldAccounting.liveCount - 1 && now.liveCount == 1)
        #expect(now.countRevision == oldAccounting.countRevision + 1 && now.retirement == nil)
        try Rows.absentReference(h.context(), target.original.referenceID)
        let saved = try prior.snapshot(h)
        #expect(saved.release.state.package.allocated == old.release.state.package.allocated - oldAccounting.byteCount)
        let projection = try SharedMediaNativeReleaseSurvivorProjection.maximum(saved)
        #expect(projection.maximumIdentityExcludedBytes <= oldProjection.maximumIdentityExcludedBytes)
        let liability = try SharedMediaNativeOriginalLiability.read(context: h.context(), inventoryID: h.inventoryID)
        if foreign {
            #expect(liability.entries[target.original.assetID] == nil)
            #expect(liability.retainedTargets.contains(target.original.assetID))
        } else {
            #expect(liability.entries[target.original.assetID] == oldLiability.entries[target.original.assetID])
            #expect(!liability.retainedTargets.contains(target.original.assetID))
        }
        #expect(try base.originalBytes(h, before) == bytes)
        #expect(try await owner.disposeAppReleaseOriginal(before) == after && saves == 1)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await SharedMediaNativeReceivingStagingTests().reopen(h)
        #expect(try await cold.disposeAppReleaseOriginal(before) == after)
        #expect(try base.originalBytes(h, before) == bytes)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["zeroCount", "wrongCount", "missingSurvivor", "invalidConsumer"])
    func coldSharedSuccessRequiresSurvivingOwnership(_ fault: String) async throws {
        let (h, owner, before) = try await fixture(foreign: true)
        _ = try await owner.disposeAppReleaseOriginal(before)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let c = h.context(), asset = before.plan.targets[0].original.assetID
        let count = try Rows.one(c, FetchDescriptor<SharedMediaAssetReferenceCountRecord>(predicate: #Predicate { $0.id == asset }))
        let ref = try Rows.one(c, FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.assetID == asset }))
        let packageID = ref.packageID
        let consumer = try #require(try SharedMediaConsumerLookup.one(c, packageID: packageID))
        switch fault {
        case "zeroCount": count.liveCount = 0
        case "wrongCount": count.liveCount += 1
        case "missingSurvivor": c.delete(ref)
        default: consumer.kindRaw = "queue"
        }
        try c.save()
        #expect(throws: (any Error).self) { _ = try prior.snapshot(h) }
        // Test the actual cold API too: opening may itself reject corrupt storage.
        do {
            let cold = try await SharedMediaNativeReceivingStagingTests().reopen(h)
            await #expect(throws: (any Error).self) { _ = try await cold.disposeAppReleaseOriginal(before) }
            #expect(await cold.invalidateAndAwaitForAccountTransition())
        } catch { /* The registered owner rejects the corrupted persisted graph. */ }
    }

    func fixture(foreign: Bool, count: Int = 1) async throws -> (Store, SharedMediaNativeOriginalOwner, Values.Progress) {
        let h = try Store(receiving: true, fenceBootstrap: true), owner = try await h.open()
        let sourceID = foreign ? UUID() : h.packageID
        if foreign {
            let c = h.context(), id = h.packageID
            c.delete(try h.package(in: c))
            c.delete(try Rows.one(c, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == id })))
            try c.save()
        }
        let request = try await owner.prepareAppOriginal(packageID: sourceID, draftGeneration: h.draft, ordinal: 0, kind: .picker)
        let bytes = PhotoPreparationTestHarness.image(), acquired = try await owner.acquireAppOriginal(request) { bytes }
        let source = PhotoOriginalReference(ownerID: h.ownerID, packageID: sourceID, referenceID: request.referenceID,
            assetID: request.assetID, assetGeneration: request.assetGeneration, draftGeneration: h.draft,
            referenceRevision: acquired.referenceRevision)
        let share = try await owner.prepareAppOriginalShare(source, packageID: foreign ? h.packageID : UUID(), draftGeneration: h.draft)
        let shared = try await owner.shareAppOriginal(share)
        if foreign {
            let ready = try await owner.prepareAndDeliverAppPhoto(original: source, recipe: Self.recipe)
            let prepared = try await owner.appReceivingRequest(packageID: sourceID, pairIDs: [ready.intent().pairID],
                operationID: UUID(), queueID: UUID(), observationID: UUID(), bindingID: UUID(), generation: UUID(),
                eventID: UUID(), timestamp: Date(timeIntervalSince1970: 1_700_000_000))
            try promoteHistoricalSource(h, prepared)
        }
        let ready = try await owner.prepareAndDeliverAppPhoto(original: foreign ? shared : source, recipe: Self.recipe)
        var pairIDs = [try ready.intent().pairID]
        if count == 2 {
            let next = try await owner.prepareAppOriginal(packageID: h.packageID, draftGeneration: h.draft, ordinal: 1, kind: .picker)
            let acquired = try await owner.acquireAppOriginal(next) { bytes }
            let original = PhotoOriginalReference(ownerID: h.ownerID, packageID: h.packageID,
                referenceID: next.referenceID, assetID: next.assetID, assetGeneration: next.assetGeneration,
                draftGeneration: h.draft, referenceRevision: acquired.referenceRevision)
            let pair = try await owner.prepareAndDeliverAppPhoto(original: original, recipe: Self.recipe)
            pairIDs.append(try pair.intent().pairID)
        }
        let prepared = try await owner.stageAppReceiving(packageID: h.packageID, draftGeneration: h.draft,
            pairIDs: pairIDs)
        _ = try await owner.receiveAppPrepared(prepared)
        let admission = try await owner.appReleaseStageRequest(prepared, releaseID: UUID())
        _ = try await owner.stageAppRelease(admission)
        let progress = try await owner.startAppRelease(admission.request)
        let retiring = try await owner.retireAppReleasePair(progress)
        return (h, owner, try await owner.removeAppReleasePair(retiring))
    }

    // Controlled historical nonqueue consumer fixture using the real freeze
    // descriptor. No source slot, queue, job, event or AI operation is created.
    private func promoteHistoricalSource(_ h: Store, _ prepared: SharedMediaNativeAppReceivingRequest) throws {
        let c = h.context(), id = prepared.package.id
        let package = try h.package(id, in: c)
        let member = try Rows.one(c, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == id }))
        let value = SharedMediaNativeConsumerCohort(format: .receiving, bindingID: prepared.cohort.bindingID,
            originQueueID: prepared.cohort.originQueueID, observationID: prepared.cohort.observationID,
            executionKind: "ordinaryV1", inferenceGeneration: prepared.cohort.inferenceGeneration,
            freeze: .init(bytes: try prepared.freeze.commit.encoded()), membership: prepared.member.bytes)
        let row = SharedMediaConsumerRecord(id: value.bindingID, kindRaw: "localScan", consumerID: value.observationID,
            originQueueID: value.originQueueID, observationID: value.observationID, inventoryID: h.inventoryID,
            inventoryGeneration: prepared.freeze.commit.inventoryGeneration, ownerID: h.ownerID, packageID: id,
            draftGeneration: h.draft, frozenPackageRevision: try prepared.freeze.commit.packageRevision,
            contractVersion: SharedMediaNativeConsumerGraph.contract, digestVersion: 1, cohortSHA256: try value.digest(),
            executionKindRaw: "ordinaryV1", inferenceGeneration: value.inferenceGeneration)
        row.cohortData = try value.encoded(); row.revision += 1
        let frozen = try prepared.frozenPackage(), inventoryID = h.inventoryID
        let inventory = try Rows.one(c, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        let freezePackageRevision = try prepared.freeze.commit.packageRevision
        try #require(inventory.revision == prepared.freeze.commit.beforeInventoryRevision)
        try #require(frozen.revision == freezePackageRevision)
        // The request describes an uncommitted freeze. Reproduce its inventory
        // advance and the separate historical promotion's package advance.
        // A retained package is exactly one revision beyond the frozen package.
        inventory.revision = try prepared.freeze.commit.inventoryRevision
        package.supportingContextData = frozen.envelope; package.phaseRaw = frozen.phase
        package.accountingTierRaw = "retained"
        package.revision = try SharedMediaStoragePolicy.add(frozen.revision, 1)
        c.delete(member); c.insert(row); try c.save()
        #expect(try SharedMediaNativeConsumerGraph.validateScoped(row, context: c, format: .appV2) == value)
    }
}
