import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Native app never-started plan closure", .serialized)
@MainActor
struct SharedMediaNativeAppPlanClosureTests {
    typealias Store = SharedMediaNativeAppMetadataTests.Store
    private static let recipe = SharedMediaNativePreparationRecipe(format: .stillImage, isPro: false,
        cropDisplaySize: nil, quarterTurns: 0, scale: 1, offsetX: 0, offsetY: 0)

    @Test(arguments: ["warm", "cold", "receiving"])
    func exactClosurePreservesOriginalAndOtherPackages(_ mode: String) async throws {
        let h = try Store(receiving: mode == "receiving")
        var owner: SharedMediaNativeOriginalOwner
        if mode == "receiving" { owner = try await h.openWithReceivingConsumer().0 } else { owner = try await h.open() }
        let (original, plan) = try await planned(h, owner)
        let intent = try SharedMediaNativeDerivativeIntent.decode(plan.intent.bytes)
        let originalURL = h.parent.appendingPathComponent("photo/PhotoPreparation").appendingPathComponent(intent.preparation.original.token)
        let originalBytes = try Data(contentsOf: originalURL)
        let ordinary = try h.package(h.ordinaryID).supportingContextData
        let other = try otherMembers(h)
        if mode == "cold" {
            #expect(await owner.invalidateAndAwaitForAccountTransition())
            owner = try await reopen(h)
        }
        var saves = 0
        try owner.setPreparationFault { if $0 == .beforePlanClosureSave { saves += 1 } }
        try await owner.abandonAppPlan(plan)
        #expect(saves == 1)
        let package = try h.package()
        #expect(package.revision == plan.packageRevision + 1 && package.phaseRaw == "draftOwned")
        let envelope = try SharedMediaNativeDraftEnvelope.decode(package.supportingContextData)
        #expect(envelope.intents.isEmpty && envelope.attempt == nil)
        #expect(try Data(contentsOf: originalURL) == originalBytes)
        #expect(try h.package(h.ordinaryID).supportingContextData == ordinary)
        #expect(try otherMembers(h) == other)
        let packageID = h.packageID
        let member = try #require(try h.context().fetch(FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == packageID })).first)
        let membership = try SharedMediaMembership.decode(member.membersData)
        #expect(membership.ids(.pair).isEmpty && membership.ids(.derivative).isEmpty)
        let before = try SharedMediaMembership.decode(plan.membership)
        for kind in SharedMediaMembership.Kind.allCases where kind != .pair && kind != .derivative {
            #expect(membership.ids(kind) == before.ids(kind))
        }
        await #expect(throws: (any Error).self) { try await owner.abandonAppPlan(plan) }
        #expect(saves == 1)
        try owner.setPreparationFault(nil)
        let fresh = try await owner.reserveAppPreparation(original: original, recipe: Self.recipe)
        try await owner.abandonAppPreparation(fresh)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await reopen(h)
        await #expect(throws: (any Error).self) { _ = try await cold.savedAppPlan(packageID: h.packageID, pairID: intent.pairID) }
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["final", "emptyPartial", "partial", "symlink"])
    func anyUnownedDestinationPreventsRelease(_ kind: String) async throws {
        let h = try Store(), owner = try await h.open(), (_, plan) = try await planned(h, owner)
        let url = try destination(h, plan)
        if kind == "symlink" { try FileManager.default.createSymbolicLink(at: url, withDestinationURL: url.deletingLastPathComponent()) }
        else {
            let target = kind == "final" ? url : URL(fileURLWithPath: url.path + ".partial")
            try (kind == "emptyPartial" ? Data() : Data("unowned".utf8)).write(to: target)
        }
        var saves = 0
        try owner.setPreparationFault { if $0 == .beforePlanClosureSave { saves += 1 } }
        await #expect(throws: (any Error).self) { try await owner.abandonAppPlan(plan) }
        #expect(saves == 0)
        try await unchanged(h, owner, plan)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["latePartial", "parentReplacement", "memberRevision"])
    func finalSynchronousSealRejectsChangesAfterInspection(_ kind: String) async throws {
        let h = try Store(), owner = try await h.open(), (_, plan) = try await planned(h, owner)
        let url = try destination(h, plan)
        var saves = 0
        try owner.setPreparationFault { point in
            guard point == .beforePlanClosureSave else { return }; saves += 1
            if kind == "latePartial" { try Data().write(to: URL(fileURLWithPath: url.path + ".partial")) }
            else if kind == "parentReplacement" {
                let parent = url.deletingLastPathComponent(), moved = parent.appendingPathExtension("held")
                try FileManager.default.moveItem(at: parent, to: moved)
                try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
            } else {
                let c = h.context(), id = h.packageID
                let row = try #require(try c.fetch(FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == id })).first)
                row.revision += 1; try c.save()
            }
        }
        await #expect(throws: (any Error).self) { try await owner.abandonAppPlan(plan) }
        #expect(saves == 1)
        #expect(try h.package().revision == plan.packageRevision)
        let intent = try SharedMediaNativeDerivativeIntent.decode(plan.intent.bytes), id = intent.pairID
        #expect(try h.context().fetchCount(FetchDescriptor<SharedMediaDerivativePairRecord>(predicate: #Predicate { $0.id == id })) == 1)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["beforeSave", "afterSave", "readbackLoss"])
    func uncertainClosureNeverRepeatsDeletion(_ fault: String) async throws {
        let h = try Store(), owner = try await h.open(), (_, plan) = try await planned(h, owner)
        var saves = 0, saved = false
        try owner.setPreparationFault { point in
            if point == .beforePlanClosureSave { saves += 1 }
            if point == .afterPlanClosureSave { saved = true }
            if (fault == "beforeSave" && point == .beforePlanClosureSave) || (fault == "afterSave" && point == .afterPlanClosureSave)
                || (fault == "readbackLoss" && saved && point == .beforeReadback) { throw SharedMediaStorageFailure.unavailable }
        }
        if fault == "afterSave" { try await owner.abandonAppPlan(plan) }
        else { await #expect(throws: (any Error).self) { try await owner.abandonAppPlan(plan) } }
        #expect(saves == 1)
        try owner.setPreparationFault(nil)
        if fault == "beforeSave" { try await unchanged(h, owner, plan) }
        else {
            #expect(try SharedMediaNativeDraftEnvelope.decode(h.package().supportingContextData).intents.isEmpty)
            await #expect(throws: (any Error).self) { try await owner.abandonAppPlan(plan) }
            #expect(try h.package().revision == plan.packageRevision + 1)
        }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    private func planned(_ h: Store, _ owner: SharedMediaNativeOriginalOwner) async throws -> (PhotoOriginalReference, SharedMediaNativePairPlan) {
        let request = try await owner.prepareAppOriginal(packageID: h.packageID, draftGeneration: h.draft, ordinal: 0, kind: .picker)
        let bytes = PhotoPreparationTestHarness.image(), result = try await owner.acquireAppOriginal(request) { bytes }
        let original = PhotoOriginalReference(ownerID: h.ownerID, packageID: h.packageID, referenceID: request.referenceID,
            assetID: request.assetID, assetGeneration: request.assetGeneration, draftGeneration: h.draft, referenceRevision: result.referenceRevision)
        let plan = try await owner.prepareAndPlanAppPhoto(original: original, recipe: Self.recipe)
        return (original, plan)
    }
    private func destination(_ h: Store, _ plan: SharedMediaNativePairPlan) throws -> URL {
        let intent = try SharedMediaNativeDerivativeIntent.decode(plan.intent.bytes)
        return h.parent.appendingPathComponent("photo/PhotoPreparation").appendingPathComponent(h.ownerID.uuidString.lowercased())
            .appendingPathComponent(h.packageID.uuidString.lowercased()).appendingPathComponent(intent.ai.assetID.uuidString.lowercased())
    }
    private func unchanged(_ h: Store, _ owner: SharedMediaNativeOriginalOwner, _ plan: SharedMediaNativePairPlan) async throws {
        let intent = try SharedMediaNativeDerivativeIntent.decode(plan.intent.bytes)
        #expect(try await owner.savedAppPlan(packageID: h.packageID, pairID: intent.pairID) == plan)
        #expect(try h.package().revision == plan.packageRevision)
    }
    private func otherMembers(_ h: Store) throws -> [UUID: Data] {
        let id = h.packageID
        return Dictionary(uniqueKeysWithValues: try h.context().fetch(FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id != id })).map { ($0.id, $0.membersData) })
    }
    private func reopen(_ h: Store) async throws -> SharedMediaNativeOriginalOwner {
        let owner = try SharedMediaNativeOriginalOwner.appDispatch(account: PhotoOriginalPreparationOwner.syntheticAccount(ownerID: h.ownerID, runtime: h.runtime), drain: .init())
        _ = try await owner.openApp(container: h.container, parent: h.parent, inventoryID: h.inventoryID); return owner
    }
}
