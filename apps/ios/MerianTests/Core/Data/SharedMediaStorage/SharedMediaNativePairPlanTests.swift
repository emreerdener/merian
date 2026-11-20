import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Native prepared pair plans", .serialized)
@MainActor
struct SharedMediaNativePairPlanTests {
    private typealias Harness = SharedMediaNativePreparationTests.Harness
    private static let recipe = SharedMediaNativePreparationRecipe(format: .stillImage, isPro: false,
        cropDisplaySize: nil, quarterTurns: 0, scale: 1, offsetX: 0, offsetY: 0)
    private enum Fault: Error { case injected }

    @Test func planReopensWithoutProcessingOrFilesAndExplicitAbandonmentPreservesDraft() async throws {
        let h = try Harness(), owner = try await h.open(), original = try await h.acquire(owner)
        let edit = try await owner.prepareMetadata(packageID: h.packageID, draftGeneration: h.draft,
            contexts: [.init(freeText: "  retained supporting description  ")])
        _ = try await owner.saveMetadata(edit)
        let before = try h.state()
        let output = try await owner.qualifyPhotoPreparation(original: original, recipe: Self.recipe, savePlan: true)
        let plan = try #require(try await owner.plannedPreparation(packageID: h.packageID))
        #expect(plan.intent.bytes == (try output.intent.encoded()))
        #expect(plan.inventoryRevision == before.inventory + 2 && plan.packageRevision == before.package + 2)
        #expect(plan.membershipRevision == before.memberRevision + 1)
        #expect(try await owner.activePreparation(packageID: h.packageID) == nil)
        #expect(try await owner.snapshot().requiresRecovery)
        try requireOnlyOriginal(h, original: original)
        await #expect(throws: (any Error).self) { try await owner.prepareMetadata(packageID: h.packageID, draftGeneration: h.draft, contexts: []) }
        await #expect(throws: (any Error).self) { try await owner.prepareRemoval(original) }
        await #expect(throws: (any Error).self) { try await owner.prepareShare(original, packageID: UUID(), draftGeneration: UUID()) }
        await #expect(throws: (any Error).self) { try await owner.qualifyPhotoPreparation(original: original, recipe: Self.recipe, savePlan: true) }
        let saved = try h.state()
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await h.open()
        #expect(try await cold.plannedPreparation(packageID: h.packageID) == plan)
        #expect(try h.state() == saved)
        try await cold.abandonPlannedPreparation(plan)
        let after = try h.state(), envelope = try SharedMediaNativeDraftEnvelope.decode(after.envelope)
        #expect(after.phase == "draftOwned" && after.members == before.members)
        #expect(after.inventory == plan.inventoryRevision + 1 && after.package == plan.packageRevision + 1)
        #expect(after.memberRevision == plan.membershipRevision + 1)
        #expect(envelope.sequence == 1 && envelope.contexts.first?.freeText == "  retained supporting description  ")
        #expect(!(try await cold.snapshot().requiresRecovery))
        try requireOnlyOriginal(h, original: original)
        await #expect(throws: (any Error).self) { try await cold.abandonPlannedPreparation(plan) }
        let next = try await cold.reservePreparation(original: original, recipe: Self.recipe)
        #expect(next.sequence == 2)
        await #expect(throws: (any Error).self) { try await cold.abandonPlannedPreparation(plan) }
        #expect(try await cold.activePreparation(packageID: h.packageID) == next)
        try await cold.abandonPreparation(next)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test func planInAnotherPackageBlocksReservationAtTheAdmissionGuard() async throws {
        let h = try Harness(), owner = try await h.open(), original = try await h.acquire(owner)
        let share = try await owner.prepareShare(original, packageID: UUID(), draftGeneration: UUID())
        let other = try await owner.share(share)
        try SharedMediaNativePreparationGraph.requireNoUnfinished(ModelContext(h.container))
        _ = try await owner.qualifyPhotoPreparation(original: original, recipe: Self.recipe, savePlan: true)
        let before = try h.state(), plan = try #require(try await owner.plannedPreparation(packageID: h.packageID))
        // Directly exercise the same read-only precondition called inside the
        // sealed mutation, in addition to the public owner's recovery guard.
        #expect(throws: SharedMediaStorageFailure.closed) {
            try SharedMediaNativePreparationGraph.requireNoUnfinished(ModelContext(h.container))
        }
        await #expect(throws: (any Error).self) { try await owner.reservePreparation(original: other, recipe: Self.recipe) }
        #expect(try h.state() == before)
        #expect(try await owner.plannedPreparation(packageID: h.packageID) == plan)
        #expect(try await owner.activePreparation(packageID: other.packageID) == nil)
        try await owner.abandonPlannedPreparation(plan)
        try SharedMediaNativePreparationGraph.requireNoUnfinished(ModelContext(h.container))
        let next = try await owner.reservePreparation(original: other, recipe: Self.recipe)
        try await owner.abandonPreparation(next)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: [SharedMediaNativePreparationBoundary.beforePairSave, .afterPairSave])
    func planSaveBoundaryRetainsExactlyOneRecoveryState(_ boundary: SharedMediaNativePreparationBoundary) async throws {
        let h = try Harness(), owner = try await h.open(), original = try await h.acquire(owner)
        try owner.setPreparationFault { if $0 == boundary { throw Fault.injected } }
        if boundary == .beforePairSave {
            await #expect(throws: Fault.self) { try await owner.qualifyPhotoPreparation(original: original, recipe: Self.recipe, savePlan: true) }
            #expect(try await owner.plannedPreparation(packageID: h.packageID) == nil)
            let attempt = try #require(try await owner.activePreparation(packageID: h.packageID))
            try owner.setPreparationFault(nil)
            try await owner.abandonPreparation(attempt)
        } else {
            let output = try await owner.qualifyPhotoPreparation(original: original, recipe: Self.recipe, savePlan: true)
            let plan = try #require(try await owner.plannedPreparation(packageID: h.packageID))
            #expect(plan.intent.bytes == (try output.intent.encoded()))
            // The same injected post-save error must acknowledge exact removal.
            try await owner.abandonPlannedPreparation(plan)
            #expect(try await owner.plannedPreparation(packageID: h.packageID) == nil)
        }
        try requireOnlyOriginal(h, original: original)
        #expect(!(try await owner.snapshot().requiresRecovery))
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func failedAbandonmentPreservesPlanAndCannotReleaseNewerPlan() async throws {
        let h = try Harness(), owner = try await h.open(), original = try await h.acquire(owner)
        _ = try await owner.qualifyPhotoPreparation(original: original, recipe: Self.recipe, savePlan: true)
        let plan = try #require(try await owner.plannedPreparation(packageID: h.packageID)), before = try h.state()
        try owner.setPreparationFault { if $0 == .beforePairSave { throw Fault.injected } }
        await #expect(throws: Fault.self) { try await owner.abandonPlannedPreparation(plan) }
        #expect(try h.state() == before)
        #expect(try await owner.plannedPreparation(packageID: h.packageID) == plan)
        try owner.setPreparationFault(nil)
        try await owner.abandonPlannedPreparation(plan)
        _ = try await owner.qualifyPhotoPreparation(original: original, recipe: Self.recipe, savePlan: true)
        let next = try #require(try await owner.plannedPreparation(packageID: h.packageID))
        await #expect(throws: (any Error).self) { try await owner.abandonPlannedPreparation(plan) }
        #expect(try await owner.plannedPreparation(packageID: h.packageID) == next)
        try await owner.abandonPlannedPreparation(next)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func plannedBudgetTransfersOutputReservationExactlyOnce() async throws {
        let h = try Harness(), owner = try await h.open(), original = try await h.acquire(owner)
        let output = try await owner.qualifyPhotoPreparation(original: original, recipe: Self.recipe, savePlan: true)
        let context = ModelContext(h.container), inventory = try #require(context.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first)
        let budget = try SharedMediaNativeAcquisitionBudget.evaluate(context: context, inventory: inventory)
        #expect(budget.metadataByPackage[h.packageID] == PhotoPreparationPolicy.metadata)
        let receipt = try #require(context.fetch(FetchDescriptor<SharedMediaAcquisitionReceiptRecord>()).first)
        guard case .completed(let request, let result) = try SharedMediaAcquisitionReceipt.read(receipt) else { throw Fault.injected }
        let state = try h.state()
        let bytes = Int64(state.envelope.count + state.members.count) + (try SharedMediaAcquisitionReceipt.metadataCharge(request: request, result: result))
        let required = SharedMediaStoragePolicy.reserve + Int64(output.ai.count + output.display.count) + PhotoPreparationPolicy.metadata - bytes
        #expect(throws: SharedMediaStorageFailure.capacity) { try budget.totals.checkAvailable(required - 1) }
        try budget.totals.checkAvailable(required)
        #expect(try context.fetchCount(FetchDescriptor<PhotoPreparationLease>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<SharedMediaAllocationRecord>()) == 1)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["legacyTag", "missingChild", "extraChild", "unexpectedInode", "mismatchedEpoch", "changedDigest", "outputPhase"])
    func malformedPlanNeverReceivesAuthority(_ mutation: String) async throws {
        let h = try Harness(), owner = try await h.open(), original = try await h.acquire(owner)
        _ = try await owner.qualifyPhotoPreparation(original: original, recipe: Self.recipe, savePlan: true)
        let context = ModelContext(h.container)
        let pair = try #require(context.fetch(FetchDescriptor<SharedMediaDerivativePairRecord>()).first)
        let works = try context.fetch(FetchDescriptor<SharedMediaDerivativeWorkRecord>())
        let work = try #require(works.first)
        switch mutation {
        case "legacyTag": pair.contractVersion = "sharedDerivativeV1"
        case "missingChild": context.delete(work)
        case "extraChild": context.insert(SharedMediaDerivativeWorkRecord(id: UUID(), pairID: pair.id, roleRaw: work.roleRaw,
            assetID: UUID(), assetGeneration: UUID(), referenceID: UUID(), leaseID: UUID(), writerEpoch: work.writerEpoch,
            byteCount: work.byteCount, sha256: work.sha256, contentType: work.contentType))
        case "unexpectedInode": work.partialInode = 1
        case "mismatchedEpoch": work.writerEpoch = UUID()
        case "changedDigest": work.sha256 = String(repeating: "0", count: 64)
        default: work.phaseRaw = "completed"
        }
        try context.save()
        await #expect(throws: (any Error).self) { try await owner.snapshot() }
        #expect(try Data(contentsOf: h.file(original)) == h.bytes)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        await #expect(throws: (any Error).self) { try await h.open() }
    }

    private func requireOnlyOriginal(_ h: Harness, original: PhotoOriginalReference) throws {
        #expect(try Data(contentsOf: h.file(original)) == h.bytes)
        #expect(try FileManager.default.contentsOfDirectory(atPath: h.file(original).deletingLastPathComponent().path).count == 1)
        let context = ModelContext(h.container)
        #expect(try context.fetchCount(FetchDescriptor<PhotoPreparationAsset>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<SharedMediaAssetReferenceCountRecord>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<SharedMediaAllocationRecord>()) == 1)
    }
}
