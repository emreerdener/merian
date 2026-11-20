import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Native app photo processing and durable plans", .serialized)
@MainActor
struct SharedMediaNativeAppPairPlanTests {
    typealias Store = SharedMediaNativeAppMetadataTests.Store
    private static let recipe = SharedMediaNativePreparationRecipe(format: .stillImage, isPro: false,
        cropDisplaySize: nil, quarterTurns: 0, scale: 1, offsetX: 0, offsetY: 0)

    @Test(arguments: [false, true])
    func exactPlanSurvivesReopenWithoutReprocessing(_ receiving: Bool) async throws {
        let h = try Store(receiving: receiving)
        let owner: SharedMediaNativeOriginalOwner
        if receiving { owner = try await h.openWithReceivingConsumer().0 } else { owner = try await h.open() }
        let original = try await acquire(h, owner), before = try h.package().revision
        let packageID = h.packageID
        let memberRow = try #require(try h.context().fetch(FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == packageID })).first)
        let memberBefore = try SharedMediaMembership.decode(memberRow.membersData)
        let ordinaryBefore = try h.package(h.ordinaryID).supportingContextData
        var fileEpochs: [UUID] = [], attemptEpoch: UUID?, boundaries = 0
        try owner.setPreparationFault({ point in
            guard point == .beforePairSave else { return }
            boundaries += 1
            let blob = try #require(try SharedMediaNativeDraftEnvelope.decode(h.package().supportingContextData).attempt)
            attemptEpoch = try SharedMediaNativePreparationAttempt.decode(blob.bytes).writerEpoch
        }, fileEpochObserved: { fileEpochs.append($0) })
        let plan = try await owner.prepareAndPlanAppPhoto(original: original, recipe: Self.recipe)
        let intent = try SharedMediaNativeDerivativeIntent.decode(plan.intent.bytes)
        #expect(plan.packageRevision == before + 2 && boundaries == 1)
        let fileEpoch = try #require(fileEpochs.first), ownerEpoch = try #require(attemptEpoch)
        #expect(fileEpochs.count == 2 && fileEpochs.allSatisfy { $0 == fileEpoch })
        #expect(plan.writerEpoch == fileEpoch && intent.preparation.writerEpoch == ownerEpoch)
        for id in [intent.ai.id, intent.display.id] {
            let work = try #require(try h.context().fetch(FetchDescriptor<SharedMediaDerivativeWorkRecord>(predicate: #Predicate { $0.id == id })).first)
            #expect(work.writerEpoch == fileEpoch)
        }
        try owner.setPreparationFault(nil)
        #expect(try await owner.activeAppPreparation(packageID: h.packageID) == nil)
        let membership = try SharedMediaMembership.decode(plan.membership)
        #expect(membership.ids(.pair) == [intent.pairID])
        #expect(Set(membership.ids(.derivative)) == Set([intent.ai.id, intent.display.id]))
        for kind in SharedMediaMembership.Kind.allCases where kind != .pair && kind != .derivative {
            #expect(membership.ids(kind) == memberBefore.ids(kind))
        }
        #expect(try h.package(h.ordinaryID).supportingContextData == ordinaryBefore)
        #expect(try Data(contentsOf: file(h, intent)) == PhotoPreparationTestHarness.image())
        #expect(try h.context().fetchCount(FetchDescriptor<PhotoPreparationLease>()) == 0)
        #expect(try await owner.savedAppPlan(packageID: h.packageID, pairID: intent.pairID) == plan)
        await #expect(throws: (any Error).self) { _ = try await owner.prepareAndPlanAppPhoto(original: original, recipe: Self.recipe) }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await reopen(h)
        #expect(try await cold.savedAppPlan(packageID: h.packageID, pairID: intent.pairID) == plan)
        await #expect(throws: (any Error).self) { _ = try await cold.prepareAndPlanAppPhoto(original: original, recipe: Self.recipe) }
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["beforePairSave", "afterPairSave", "readbackLoss"])
    func uncertainPlanNeverRepeatsProcessingOrSave(_ fault: String) async throws {
        let h = try Store(), owner = try await h.open(), original = try await acquire(h, owner)
        var saves = 0, saved = false
        try owner.setPreparationFault { point in
            if point == .beforePairSave { saves += 1 }
            if point == .afterPairSave { saved = true }
            if (fault == "beforePairSave" && point == .beforePairSave) || (fault == "afterPairSave" && point == .afterPairSave)
                || (fault == "readbackLoss" && saved && point == .beforeReadback) { throw SharedMediaStorageFailure.unavailable }
        }
        if fault == "afterPairSave" { _ = try await owner.prepareAndPlanAppPhoto(original: original, recipe: Self.recipe) }
        else { await #expect(throws: (any Error).self) { _ = try await owner.prepareAndPlanAppPhoto(original: original, recipe: Self.recipe) } }
        #expect(saves == 1)
        try owner.setPreparationFault(nil)
        await #expect(throws: (any Error).self) { _ = try await owner.prepareAndPlanAppPhoto(original: original, recipe: Self.recipe) }
        let envelope = try SharedMediaNativeDraftEnvelope.decode(h.package().supportingContextData)
        #expect(envelope.intents.count == (fault == "beforePairSave" ? 0 : 1))
        if fault == "beforePairSave" {
            let attempt = try #require(try await owner.activeAppPreparation(packageID: h.packageID))
            try await owner.abandonAppPreparation(attempt)
        } else {
            let blob = try #require(envelope.intents.first), intent = try SharedMediaNativeDerivativeIntent.decode(blob.bytes)
            let plan = try await owner.savedAppPlan(packageID: h.packageID, pairID: intent.pairID)
            #expect(plan.intent == blob)
        }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["bootstrap", "member", "original", "physical", "consumer", "lease"])
    func finalBoundaryRejectsDriftWithoutPlanRows(_ kind: String) async throws {
        let h = try Store(receiving: kind == "consumer")
        let owner: SharedMediaNativeOriginalOwner
        var consumerID: UUID?
        if kind == "consumer" { (owner, consumerID) = try await h.openWithReceivingConsumer() } else { owner = try await h.open() }
        let original = try await acquire(h, owner)
        var boundaries = 0
        try owner.setPreparationFault { point in
            guard point == .beforePairSave else { return }
            boundaries += 1
            let c = h.context()
            if kind == "bootstrap" {
                let id = h.inventoryID
                let row = try #require(try c.fetch(FetchDescriptor<SharedMediaMembershipBootstrapRecord>(predicate: #Predicate { $0.id == id })).first)
                row.revision += 1
            } else if kind == "member" {
                let id = h.packageID
                let row = try #require(try c.fetch(FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == id })).first)
                row.revision += 1
            } else if kind == "consumer" {
                let id = try #require(consumerID)
                let row = try #require(try SharedMediaConsumerLookup.one(c, id: id))
                row.revision += 1
            } else if kind == "lease" {
                let id = original.assetID
                let asset = try #require(try c.fetch(FetchDescriptor<PhotoPreparationAsset>(predicate: #Predicate { $0.id == id })).first)
                asset.cleanupStateRaw = "held"
            } else if kind == "physical" {
                let attempt = try #require(try SharedMediaNativeDraftEnvelope.decode(h.package().supportingContextData).attempt)
                let value = try SharedMediaNativePreparationAttempt.decode(attempt.bytes)
                let url = h.parent.appendingPathComponent("photo/PhotoPreparation").appendingPathComponent(value.original.token)
                try Data("changed".utf8).write(to: url, options: .atomic)
            } else {
                let id = original.referenceID
                let row = try #require(try c.fetch(FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.id == id })).first)
                row.revision += 1
            }
            if c.hasChanges { try c.save() }
        }
        await #expect(throws: (any Error).self) { _ = try await owner.prepareAndPlanAppPhoto(original: original, recipe: Self.recipe) }
        #expect(boundaries == 1)
        let id = h.packageID
        #expect(try h.context().fetchCount(FetchDescriptor<SharedMediaDerivativePairRecord>(predicate: #Predicate { $0.packageID == id })) == 0)
        #expect(try SharedMediaNativeDraftEnvelope.decode(h.package().supportingContextData).attempt != nil)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func accountTransitionWaitsForProcessorAndLeavesAttempt() async throws {
        let h = try Store(), owner = try await h.open(), original = try await acquire(h, owner)
        let started = ImageFocusEngineTests.Signal(), registered = ImageFocusEngineTests.Signal()
        let invalidated = ImageFocusEngineTests.Signal(), release = DispatchSemaphore(value: 0)
        let worker = ImageFocusWorkerState.qualification(worker: {
            Task { await started.open() }; release.wait(); return .noCandidates
        }, drainRegistered: { Task { await registered.open() } })
        defer { release.signal() }
        try owner.setPreparationFault(nil, focusFactory: .qualification(worker))
        let preparation = Task {
            do { return try await owner.prepareAndPlanAppPhoto(original: original, recipe: Self.recipe) }
            catch { await started.open(); await registered.open(); throw error }
        }
        await started.wait()
        let transition = Task { let result = await owner.invalidateAndAwaitForAccountTransition(); await invalidated.open(); return result }
        await registered.wait()
        #expect(!(await invalidated.isOpen))
        release.signal()
        await #expect(throws: (any Error).self) { _ = try await preparation.value }
        #expect(await transition.value)
        let cold = try await reopen(h)
        let attempt = try #require(try await cold.activeAppPreparation(packageID: h.packageID))
        #expect(try h.context().fetchCount(FetchDescriptor<SharedMediaDerivativePairRecord>()) == 0)
        try await cold.abandonAppPreparation(attempt)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    private func acquire(_ h: Store, _ owner: SharedMediaNativeOriginalOwner) async throws -> PhotoOriginalReference {
        let request = try await owner.prepareAppOriginal(packageID: h.packageID, draftGeneration: h.draft, ordinal: 0, kind: .picker)
        let bytes = PhotoPreparationTestHarness.image()
        let result = try await owner.acquireAppOriginal(request) { bytes }
        return .init(ownerID: h.ownerID, packageID: h.packageID, referenceID: request.referenceID, assetID: request.assetID,
            assetGeneration: request.assetGeneration, draftGeneration: h.draft, referenceRevision: result.referenceRevision)
    }
    private func reopen(_ h: Store) async throws -> SharedMediaNativeOriginalOwner {
        let owner = try SharedMediaNativeOriginalOwner.appDispatch(account: PhotoOriginalPreparationOwner.syntheticAccount(ownerID: h.ownerID, runtime: h.runtime), drain: .init())
        _ = try await owner.openApp(container: h.container, parent: h.parent, inventoryID: h.inventoryID)
        return owner
    }
    private func file(_ h: Store, _ intent: SharedMediaNativeDerivativeIntent) -> URL {
        h.parent.appendingPathComponent("photo/PhotoPreparation").appendingPathComponent(intent.preparation.original.token)
    }
}
