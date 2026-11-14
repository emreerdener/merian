import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Native app preparation reservations", .serialized)
@MainActor
struct SharedMediaNativeAppPreparationTests {
    typealias Store = SharedMediaNativeAppMetadataTests.Store
    private static let recipe = SharedMediaNativePreparationRecipe(format: .stillImage, isPro: false,
        cropDisplaySize: nil, quarterTurns: 0, scale: 1, offsetX: 0, offsetY: 0)

    @Test func coldAttemptRequiresExplicitClosureAndPreservesOriginal() async throws {
        let h = try Store(), owner = try await h.open(), original = try await acquire(h, owner)
        let before = try h.package().supportingContextData, member = try h.memberBytes()
        let attempt = try await owner.reserveAppPreparation(original: original, recipe: Self.recipe)
        #expect(attempt.previousEnvelope == before && attempt.sequence == 1)
        #expect(try await owner.activeAppPreparation(packageID: h.packageID) == attempt)
        await #expect(throws: (any Error).self) { _ = try await owner.reserveAppPreparation(original: original, recipe: Self.recipe) }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await reopen(h)
        #expect(try await cold.activeAppPreparation(packageID: h.packageID) == attempt)
        try await cold.abandonAppPreparation(attempt)
        #expect(try await cold.activeAppPreparation(packageID: h.packageID) == nil)
        #expect(try h.package().phaseRaw == "draftOwned")
        #expect(try h.memberBytes() == member)
        #expect(try Data(contentsOf: file(h, attempt)) == PhotoPreparationTestHarness.image())
        let next = try await cold.reserveAppPreparation(original: original, recipe: Self.recipe)
        #expect(next.sequence == 2 && next.writerEpoch != attempt.writerEpoch && next.operationID != attempt.operationID)
        await #expect(throws: (any Error).self) { try await cold.abandonAppPreparation(attempt) }
        #expect(try await cold.activeAppPreparation(packageID: h.packageID) == next)
        try await cold.abandonAppPreparation(next)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["beforeSave", "afterSave", "readbackLoss"])
    func uncertainReservationNeverRepeatsItsSave(_ fault: String) async throws {
        let h = try Store(), owner = try await h.open(), original = try await acquire(h, owner)
        let before = try h.package().revision
        var saves = 0, saved = false
        try owner.setPreparationFault { point in
            if point == .beforeSave { saves += 1 }
            if point == .afterSave { saved = true }
            if (fault == "beforeSave" && point == .beforeSave) || (fault == "afterSave" && point == .afterSave)
                || (fault == "readbackLoss" && saved && point == .beforeReadback) { throw SharedMediaStorageFailure.unavailable }
        }
        if fault == "afterSave" { _ = try await owner.reserveAppPreparation(original: original, recipe: Self.recipe) }
        else { await #expect(throws: (any Error).self) { _ = try await owner.reserveAppPreparation(original: original, recipe: Self.recipe) } }
        #expect(saves == 1)
        #expect(try h.package().revision == before + (fault == "beforeSave" ? 0 : 1))
        try owner.setPreparationFault(nil)
        if fault != "beforeSave" {
            let exact = try #require(try await owner.activeAppPreparation(packageID: h.packageID))
            await #expect(throws: (any Error).self) { _ = try await owner.reserveAppPreparation(original: original, recipe: Self.recipe) }
            #expect(saves == 1)
            try await owner.abandonAppPreparation(exact)
        }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["beforeSave", "afterSave", "readbackLoss"])
    func uncertainClosureRecoversByInspectionWithoutAnotherSave(_ fault: String) async throws {
        let h = try Store(), owner = try await h.open(), original = try await acquire(h, owner)
        let attempt = try await owner.reserveAppPreparation(original: original, recipe: Self.recipe)
        var saves = 0, saved = false
        try owner.setPreparationFault { point in
            if point == .beforeSave { saves += 1 }
            if point == .afterSave { saved = true }
            if (fault == "beforeSave" && point == .beforeSave) || (fault == "afterSave" && point == .afterSave)
                || (fault == "readbackLoss" && saved && point == .beforeReadback) { throw SharedMediaStorageFailure.unavailable }
        }
        if fault == "afterSave" { try await owner.abandonAppPreparation(attempt) }
        else { await #expect(throws: (any Error).self) { try await owner.abandonAppPreparation(attempt) } }
        #expect(saves == 1)
        try owner.setPreparationFault(nil)
        #expect(try await owner.activeAppPreparation(packageID: h.packageID) == (fault == "beforeSave" ? attempt : nil))
        if fault == "beforeSave" { try await owner.abandonAppPreparation(attempt) }
        else { await #expect(throws: (any Error).self) { try await owner.abandonAppPreparation(attempt) } }
        #expect(try Data(contentsOf: file(h, attempt)) == PhotoPreparationTestHarness.image())
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["bootstrap", "package", "member", "original", "asset", "lease", "pair"], [false, true])
    func preSaveDriftCannotBeOverwritten(_ target: String, _ abandoning: Bool) async throws {
        let h = try Store(), owner = try await h.open(), original = try await acquire(h, owner)
        let attempt = abandoning ? try await owner.reserveAppPreparation(original: original, recipe: Self.recipe) : nil
        let before = try h.package().supportingContextData
        try owner.setPreparationFault { point in
            guard point == .beforeSave else { return }
            let context = h.context()
            switch target {
            case "bootstrap": try #require(try context.fetch(FetchDescriptor<SharedMediaMembershipBootstrapRecord>()).first).revision += 1
            case "package": try h.package(in: context).revision += 1
            case "member": try #require(try context.fetch(FetchDescriptor<SharedMediaPendingMembershipRecord>()).first).revision += 1
            case "asset": try #require(try context.fetch(FetchDescriptor<PhotoPreparationAsset>()).first).cleanupStateRaw = "retiring"
            case "pair":
                let inventory = try #require(try context.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first)
                context.insert(SharedMediaDerivativePairRecord(id: UUID(), nonce: UUID(), inventoryID: h.inventoryID,
                    inventoryGeneration: inventory.generation, expectedInventoryRevision: inventory.revision, ownerID: h.ownerID,
                    packageID: UUID(), draftGeneration: h.draft, originalReferenceID: original.referenceID,
                    originalReferenceRevision: original.referenceRevision, originalAssetID: original.assetID,
                    originalAssetGeneration: original.assetGeneration, ordinal: 0, expectedPackageRevision: 0, aiWorkID: UUID(), displayWorkID: UUID()))
            case "lease":
                context.insert(PhotoPreparationLease(id: UUID(), packageID: h.packageID, assetID: original.assetID,
                    ownerID: h.ownerID, processEpoch: UUID(), purposeRaw: "acquire", partialFileToken: "test.partial",
                    finalFileToken: "test", reservedByteCount: 1, allocatedByteCount: 0, writerStateRaw: "unknown", terminalProof: nil))
            default: try #require(try context.fetch(FetchDescriptor<PhotoPreparationAsset>()).first).sha256 = String(repeating: "0", count: 64)
            }
            try context.save()
        }
        await #expect(throws: (any Error).self) {
            if let attempt { try await owner.abandonAppPreparation(attempt) }
            else { _ = try await owner.reserveAppPreparation(original: original, recipe: Self.recipe) }
        }
        #expect(try h.package().supportingContextData == before)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func lowStorageAndOrdinaryPackageNeverCreateAnAttempt() async throws {
        let h = try Store(), owner = try await h.open(), original = try await acquire(h, owner)
        let before = try h.package().supportingContextData
        try owner.setPreparationFault(nil, availableBytes: 0)
        await #expect(throws: (any Error).self) { _ = try await owner.reserveAppPreparation(original: original, recipe: Self.recipe) }
        #expect(try h.package().supportingContextData == before)
        #expect(try await owner.activeAppPreparation(packageID: h.packageID) == nil)
        await #expect(throws: (any Error).self) { _ = try await owner.activeAppPreparation(packageID: h.ordinaryID) }
        #expect(try h.package(h.ordinaryID).supportingContextData == Data("ordinary-draft".utf8))
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["inventory", "package"])
    func exhaustedRevisionFailsClosedWithoutSaving(_ target: String) async throws {
        let h = try Store(), owner = try await h.open(), original = try await acquire(h, owner)
        let context = h.context(), before = try h.package().supportingContextData
        if target == "inventory" {
            try #require(try context.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first).revision = Int64.max
        } else { try h.package(in: context).revision = Int64.max }
        try context.save()
        var saves = 0
        try owner.setPreparationFault { if $0 == .beforeSave { saves += 1 } }
        await #expect(throws: (any Error).self) { _ = try await owner.reserveAppPreparation(original: original, recipe: Self.recipe) }
        #expect(saves == 0)
        #expect(try h.package().supportingContextData == before)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["none", "consumer", "work"], [false, true])
    func receivingConsumerIsPreservedAndDriftBlocksTransition(_ drift: String, _ abandoning: Bool) async throws {
        let h = try Store(receiving: true), (owner, consumerID) = try await h.openWithReceivingConsumer()
        let original = try await acquire(h, owner)
        let attempt = abandoning ? try await owner.reserveAppPreparation(original: original, recipe: Self.recipe) : nil
        let before = try h.package().supportingContextData
        let exact = SharedMediaNativeAppMetadataFacts.Consumer(try #require(try SharedMediaConsumerLookup.one(h.context(), id: consumerID)))
        if drift != "none" {
            try owner.setPreparationFault { point in
                guard point == .beforeSave else { return }
                let context = h.context()
                if drift == "consumer" { try #require(try SharedMediaConsumerLookup.one(context, id: consumerID)).revision += 1 }
                else {
                    let pair = try #require(try context.fetch(FetchDescriptor<SharedMediaDerivativePairRecord>()).first)
                    context.insert(SharedMediaDerivativeWorkRecord(id: UUID(), pairID: pair.id, roleRaw: "aiInput",
                        assetID: UUID(), assetGeneration: UUID(), referenceID: UUID(), leaseID: UUID(), writerEpoch: UUID(),
                        byteCount: 1, sha256: String(repeating: "a", count: 64), contentType: "image/jpeg"))
                }
                try context.save()
            }
            await #expect(throws: (any Error).self) {
                if let attempt { try await owner.abandonAppPreparation(attempt) }
                else { _ = try await owner.reserveAppPreparation(original: original, recipe: Self.recipe) }
            }
            #expect(try h.package().supportingContextData == before)
        } else {
            let active: SharedMediaNativePreparationAttempt
            if let attempt { active = attempt }
            else { active = try await owner.reserveAppPreparation(original: original, recipe: Self.recipe) }
            #expect(try await owner.inspectApp().consumers == 1)
            try await owner.abandonAppPreparation(active)
            #expect(SharedMediaNativeAppMetadataFacts.Consumer(try #require(try SharedMediaConsumerLookup.one(h.context(), id: consumerID))) == exact)
        }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    private func acquire(_ h: Store, _ owner: SharedMediaNativeOriginalOwner) async throws -> PhotoOriginalReference {
        let request = try await owner.prepareAppOriginal(packageID: h.packageID, draftGeneration: h.draft, ordinal: 0, kind: .picker)
        let bytes = PhotoPreparationTestHarness.image()
        let result = try await owner.acquireAppOriginal(request) { bytes }
        return .init(ownerID: h.ownerID, packageID: h.packageID, referenceID: request.referenceID, assetID: request.assetID,
            assetGeneration: request.assetGeneration, draftGeneration: h.draft, referenceRevision: result.referenceRevision)
    }
    private func reopen(_ h: Store) async throws -> SharedMediaNativeOriginalOwner {
        let owner = try SharedMediaNativeOriginalOwner.appDispatch(
            account: PhotoOriginalPreparationOwner.syntheticAccount(ownerID: h.ownerID, runtime: h.runtime), drain: .init())
        _ = try await owner.openApp(container: h.container, parent: h.parent, inventoryID: h.inventoryID)
        return owner
    }
    private func file(_ h: Store, _ attempt: SharedMediaNativePreparationAttempt) -> URL {
        h.parent.appendingPathComponent("photo/PhotoPreparation").appendingPathComponent(attempt.original.token)
    }
}
