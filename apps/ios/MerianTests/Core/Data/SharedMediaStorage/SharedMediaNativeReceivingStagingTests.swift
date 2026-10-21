import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Durable inactive native receiving staging", .serialized)
@MainActor
struct SharedMediaNativeReceivingStagingTests {
    typealias Store = SharedMediaNativeAppMetadataTests.Store
    private static let recipe = SharedMediaNativePreparationRecipe(format: .stillImage, isPro: false,
        cropDisplaySize: nil, quarterTurns: 0, scale: 1, offsetX: 0, offsetY: 0)

    @Test(arguments: [1, 2])
    func oneImmutableSlotSurvivesColdReopenWithoutAnotherSave(_ count: Int) async throws {
        let (h, owner, request) = try await SharedMediaNativeAppReceivingTests().fixture(count: count)
        let ids = try pairIDs(request), before = try facts(h)
        var saves = 0
        try owner.setMetadataFault { if $0 == .beforeSave { saves += 1 } }
        let prepared = try await owner.stageAppReceiving(packageID: h.packageID, draftGeneration: h.draft, pairIDs: ids)
        let again = try await owner.stageAppReceiving(packageID: h.packageID, draftGeneration: h.draft, pairIDs: ids)
        #expect(try prepared.encoded() == again.encoded())
        #expect(prepared.operationID != request.freeze.commit.operationID)
        #expect(saves == 1)
        try verify(h, prepared: prepared, before: before, inventoryRevision: request.header.inventory.revision + 1)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let url = try #require(h.container.configurations.first).url
        let container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        ])
        let cold = try await reopen(h, container: container)
        try cold.setMetadataFault { if $0 == .beforeSave { throw SharedMediaStorageFailure.closed } }
        let recovered = try await cold.stageAppReceiving(packageID: h.packageID, draftGeneration: h.draft, pairIDs: ids)
        #expect(try recovered.encoded() == prepared.encoded())
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["before", "after", "readback"])
    func uncertainAcknowledgementRecoversOnlyTheSavedSlot(_ fault: String) async throws {
        let (h, owner, request) = try await SharedMediaNativeAppReceivingTests().fixture()
        let ids = try pairIDs(request), before = try facts(h)
        var saves = 0, saved = false
        try owner.setMetadataFault {
            if $0 == .beforeSave { saves += 1; if fault == "before" { throw SharedMediaStorageFailure.unavailable } }
            if $0 == .afterSave { saved = true; if fault == "after" { throw SharedMediaStorageFailure.unavailable } }
            if $0 == .beforeReadback && saved && fault == "readback" { throw SharedMediaStorageFailure.unavailable }
        }
        if fault == "after" {
            _ = try await owner.stageAppReceiving(packageID: h.packageID, draftGeneration: h.draft, pairIDs: ids)
        } else {
            await #expect(throws: (any Error).self) {
                _ = try await owner.stageAppReceiving(packageID: h.packageID, draftGeneration: h.draft, pairIDs: ids)
            }
        }
        #expect(saves == 1)
        let rows = try h.context().fetch(FetchDescriptor<SharedMediaReceivingIntentRecord>())
        #expect(rows.count == (fault == "before" ? 0 : 1))
        #expect(try facts(h).packages == before.packages)
        try noReceivingRows(h)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        if fault != "before" {
            let bytes = try #require(rows.first?.preparedData), cold = try await reopen(h)
            try cold.setMetadataFault { if $0 == .beforeSave { throw SharedMediaStorageFailure.closed } }
            let recovered = try await cold.stageAppReceiving(packageID: h.packageID, draftGeneration: h.draft, pairIDs: ids)
            #expect(try recovered.encoded() == bytes)
            #expect(await cold.invalidateAndAwaitForAccountTransition())
        } else {
            #expect(try inventory(h).revision == request.header.inventory.revision)
        }
    }

    @Test func preparedTargetBlocksMutationsButUnrelatedDraftAndInspectionContinue() async throws {
        let (h, owner, request) = try await SharedMediaNativeAppReceivingTests().fixture()
        let ids = try pairIDs(request), pairID = try #require(ids.first)
        let plan = try await owner.savedAppPlan(packageID: h.packageID, pairID: pairID)
        let original = try SharedMediaNativeDerivativeIntent.decode(plan.intent.bytes).preparation.original.reference
        let pendingEdit = try await owner.prepareAppMetadata(packageID: h.packageID, draftGeneration: h.draft,
            contexts: [.init(freeText: "must not replace submitted text")])
        let prepared = try await owner.stageAppReceiving(packageID: h.packageID, draftGeneration: h.draft, pairIDs: ids)
        let before = try facts(h)
        await #expect(throws: (any Error).self) { _ = try await owner.saveAppMetadata(pendingEdit) }
        await #expect(throws: (any Error).self) {
            _ = try await owner.prepareAppMetadata(packageID: h.packageID, draftGeneration: h.draft, contexts: [])
        }
        await #expect(throws: (any Error).self) {
            _ = try await owner.prepareAppOriginal(packageID: h.packageID, draftGeneration: h.draft, ordinal: 1, kind: .picker)
        }
        await #expect(throws: (any Error).self) { _ = try await owner.reserveAppPreparation(original: original, recipe: Self.recipe) }
        await #expect(throws: (any Error).self) { _ = try await owner.recoverAppPhotoPair(packageID: h.packageID, pairID: pairID) }
        await #expect(throws: (any Error).self) { try await owner.retireAppPhotoPair(packageID: h.packageID, pairID: pairID) }
        await #expect(throws: (any Error).self) { try await owner.abandonAppPlan(plan) }
        await #expect(throws: (any Error).self) { _ = try await owner.prepareAppOriginalRemoval(original) }
        await #expect(throws: (any Error).self) {
            _ = try await owner.prepareAppOriginalShare(original, packageID: UUID(), draftGeneration: UUID())
        }
        await #expect(throws: (any Error).self) { _ = try await owner.receiveAppPhotos(request) }
        #expect(try await owner.savedAppPlan(packageID: h.packageID, pairID: pairID).intent == plan.intent)
        _ = try await owner.inspectApp()
        try await owner.recoverAppOriginalRetirements()
        try await owner.recoverAppPendingAbandonments()
        #expect(try facts(h).intents == before.intents)
        let other = UUID(), generation = UUID(), bytes = PhotoPreparationTestHarness.image()
        let acquisition = try await owner.prepareAppOriginal(packageID: other, draftGeneration: generation, ordinal: 0, kind: .picker)
        _ = try await owner.acquireAppOriginal(acquisition) { bytes }
        let edit = try await owner.prepareAppMetadata(packageID: other, draftGeneration: generation, contexts: [.init(freeText: "other draft")])
        _ = try await owner.saveAppMetadata(edit)
        #expect(try facts(h).intents == before.intents)
        #expect(try facts(h).packages[h.packageID] == before.packages[h.packageID])
        let recovered = try await owner.stageAppReceiving(packageID: h.packageID, draftGeneration: h.draft, pairIDs: ids)
        #expect(try recovered.encoded() == prepared.encoded())
        try noReceivingRows(h)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func missingOriginalBlocksFreshStagingButCannotReplaceSavedIntent() async throws {
        let (h, owner, request) = try await SharedMediaNativeAppReceivingTests().fixture()
        let ids = try pairIDs(request)
        let cohort = try SharedMediaNativeFrozenCohort.decode(request.freeze.commit.cohort.bytes)
        let original = try SharedMediaNativeDerivativeIntent.decode(#require(cohort.entries.first).intent.bytes).preparation.original
        let path = h.parent.appendingPathComponent("photo/PhotoPreparation").appendingPathComponent(original.token)
        let saved = try await owner.stageAppReceiving(packageID: h.packageID, draftGeneration: h.draft, pairIDs: ids)
        try FileManager.default.removeItem(at: path)
        let recovered = try await owner.stageAppReceiving(packageID: h.packageID, draftGeneration: h.draft, pairIDs: ids)
        #expect(try saved.encoded() == recovered.encoded())
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let (fresh, freshOwner, freshRequest) = try await SharedMediaNativeAppReceivingTests().fixture()
        let freshCohort = try SharedMediaNativeFrozenCohort.decode(freshRequest.freeze.commit.cohort.bytes)
        let token = try SharedMediaNativeDerivativeIntent.decode(#require(freshCohort.entries.first).intent.bytes).preparation.original.token
        try FileManager.default.removeItem(at: fresh.parent.appendingPathComponent("photo/PhotoPreparation").appendingPathComponent(token))
        await #expect(throws: (any Error).self) {
            _ = try await freshOwner.stageAppReceiving(packageID: fresh.packageID, draftGeneration: fresh.draft, pairIDs: pairIDs(freshRequest))
        }
        #expect(try fresh.context().fetchCount(FetchDescriptor<SharedMediaReceivingIntentRecord>()) == 0)
        #expect(try fresh.package().supportingContextData == freshRequest.package.envelope)
        #expect(await freshOwner.invalidateAndAwaitForAccountTransition())
    }

    @Test func recoveryRejectsDifferentGenerationAndOrder() async throws {
        let (h, owner, request) = try await SharedMediaNativeAppReceivingTests().fixture(count: 2)
        let ids = try pairIDs(request)
        let saved = try await owner.stageAppReceiving(packageID: h.packageID, draftGeneration: h.draft, pairIDs: ids)
        await #expect(throws: (any Error).self) {
            _ = try await owner.stageAppReceiving(packageID: h.packageID, draftGeneration: UUID(), pairIDs: ids)
        }
        await #expect(throws: (any Error).self) {
            _ = try await owner.stageAppReceiving(packageID: h.packageID, draftGeneration: h.draft, pairIDs: ids.reversed())
        }
        let recovered = try #require(try await owner.discoverAppReceivingIntent(packageID: h.packageID))
        #expect(try recovered.encoded() == saved.encoded())
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    func pairIDs(_ request: SharedMediaNativeAppReceivingRequest) throws -> [UUID] {
        try SharedMediaNativeFrozenCohort.decode(request.freeze.commit.cohort.bytes).entries.map {
            try SharedMediaNativeDerivativeIntent.decode($0.intent.bytes).pairID
        }
    }
    func inventory(_ h: Store) throws -> SharedMediaInventoryRecord {
        try #require(try h.context().fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first)
    }
    func facts(_ h: Store) throws -> SharedMediaNativeAppMetadataFacts {
        try .capture(h.context(), profile: SharedMediaNativeAppEligibility.profile(inventory(h)))
    }
    private func verify(_ h: Store, prepared: SharedMediaNativeReceivingIntent.Prepared,
                        before: SharedMediaNativeAppMetadataFacts, inventoryRevision: Int64) throws {
        let c = h.context(), inventory = try #require(try c.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first)
        let witness = try #require(SharedMediaNativeReceivingPhaseGraph.pending(c, inventory: inventory)[h.packageID])
        #expect(witness.row.preparedData == (try prepared.encoded()))
        #expect(inventory.revision == inventoryRevision)
        try before.validateStaging(c, adding: witness.row)
        let budget = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: c, inventory: inventory, ownerID: h.ownerID, format: .appV2)
        #expect((budget.metadataByPackage[h.packageID] ?? 0) >= Int64(try prepared.encoded().count))
        try noReceivingRows(h)
    }
    func noReceivingRows(_ h: Store) throws {
        let c = h.context()
        #expect(try c.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
        #expect(try c.fetchCount(FetchDescriptor<OfflineJobRecord>()) == 0)
        #expect(try c.fetchCount(FetchDescriptor<OfflineQueueEvent>()) == 0)
        #expect(try c.fetchCount(FetchDescriptor<SharedMediaConsumerRecord>()) == 0)
    }
    func reopen(_ h: Store, container: ModelContainer? = nil) async throws -> SharedMediaNativeOriginalOwner {
        let reopened: ModelContainer
        if let container {
            reopened = container
        } else {
            let schema = Schema(versionedSchema: CurrentSchema.self)
            let url = try #require(h.container.configurations.first).url
            reopened = try ModelContainer(for: schema, configurations: [
                ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
            ])
            #expect(reopened !== h.container)
        }
        let owner = try await SharedMediaNativeOriginalOwner.appDispatch(
            account: PhotoOriginalPreparationOwner.syntheticAccount(ownerID: h.ownerID, runtime: h.runtime), drain: .init())
        _ = try await owner.openApp(container: reopened, parent: h.parent, inventoryID: h.inventoryID)
        return owner
    }
}
