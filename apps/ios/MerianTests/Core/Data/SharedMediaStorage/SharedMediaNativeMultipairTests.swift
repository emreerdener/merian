import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Native two-original composition", .serialized)
@MainActor
struct SharedMediaNativeMultipairTests {
    private typealias Harness = SharedMediaNativePreparationTests.Harness
    private enum Fault: Error { case injected }
    private static let recipe = SharedMediaNativePreparationRecipe(format: .stillImage, isPro: false,
        cropDisplaySize: nil, quarterTurns: 0, scale: 1, offsetX: 0, offsetY: 0)

    @Test func lateSecondOriginalPreservesFirstPairAndBothReopen() async throws {
        let h = try Harness(), owner = try await h.open(), first = try await h.acquire(owner)
        let ready = try await owner.qualifyPreparedFiles(original: first, recipe: Self.recipe)
        let survivor = try Survivor(h, ready)
        let second = try await h.acquire(owner, ordinal: 1)
        try await survivor.require(h, owner)
        let other = try await owner.qualifyPreparedFiles(original: second, recipe: Self.recipe)
        try await survivor.require(h, owner)
        #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<PhotoPreparationReference>()) == 6)
        await #expect(throws: (any Error).self) { try await owner.preparedFileState(packageID: h.packageID) }
        await #expect(throws: (any Error).self) { try await owner.plannedPreparation(packageID: h.packageID) }
        await #expect(throws: (any Error).self) { try await owner.reservePreparation(original: first, recipe: Self.recipe) }
        await #expect(throws: (any Error).self) { try await owner.prepareRemoval(first) }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await h.open(), pairID = try other.intent().pairID
        try await survivor.require(h, cold)
        let restored = try await cold.recoverPreparedFiles(packageID: h.packageID, pairID: pairID)
        #expect(restored == other)
        try await cold.retirePreparedFiles(restored)
        try await survivor.require(h, cold)
        #expect(try Data(contentsOf: h.file(second)) == h.bytes)
        let current = try await cold.preparedFileState(packageID: h.packageID)
        try await cold.retirePreparedFiles(current)
        #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<SharedMediaDerivativePairRecord>()) == 0)
        #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<SharedMediaAllocationRecord>()) == 2)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: [SharedMediaNativePreparationBoundary.beforePairSave, .beforeFileReserve, .beforeFileCompletion, .beforeFilePublish])
    func secondPreparationInterruptionPreservesReadySurvivor(_ boundary: SharedMediaNativePreparationBoundary) async throws {
        let h = try Harness(), owner = try await h.open(), first = try await h.acquire(owner), second = try await h.acquire(owner, ordinal: 1)
        let ready = try await owner.qualifyPreparedFiles(original: first, recipe: Self.recipe), survivor = try Survivor(h, ready)
        try owner.setPreparationFault { if $0 == boundary { throw Fault.injected } }
        await #expect(throws: Fault.self) { try await owner.qualifyPreparedFiles(original: second, recipe: Self.recipe) }
        try owner.setPreparationFault(nil)
        try await survivor.require(h, owner)
        let currentFirst = try await owner.preparedFileState(packageID: h.packageID, pairID: ready.intent().pairID)
        await #expect(throws: (any Error).self) { try await owner.retirePreparedFiles(currentFirst) }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await h.open()
        if let attempt = try await cold.activePreparation(packageID: h.packageID) {
            #expect(boundary == .beforePairSave)
            try await cold.abandonPreparation(attempt)
        } else {
            let secondID = try secondPairID(h, excluding: ready.intent().pairID)
            let state = try await cold.preparedFileState(packageID: h.packageID, pairID: secondID)
            if state.phase == "planned" { try await cold.abandonPlannedPreparation(state.plan) }
            else {
                let recovered = try await cold.recoverPreparedFiles(packageID: h.packageID, pairID: secondID)
                if boundary == .beforeFilePublish { #expect(recovered.phase == "ready") }
                try await cold.retirePreparedFiles(recovered)
            }
        }
        try await survivor.require(h, cold)
        #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<SharedMediaDerivativePairRecord>()) == 1)
        #expect(try Data(contentsOf: h.file(second)) == h.bytes)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test func secondRetirementUnlinkRetryPreservesFirstPair() async throws {
        let h = try Harness(), owner = try await h.open(), first = try await h.acquire(owner), second = try await h.acquire(owner, ordinal: 1)
        let ready = try await owner.qualifyPreparedFiles(original: first, recipe: Self.recipe), survivor = try Survivor(h, ready)
        let other = try await owner.qualifyPreparedFiles(original: second, recipe: Self.recipe)
        try await owner.setPairFileFault { if $0 == .afterUnlink { throw Fault.injected } }
        await #expect(throws: Fault.self) { try await owner.retirePreparedFiles(other) }
        try await survivor.require(h, owner)
        #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<SharedMediaAllocationRecord>()) == 6)
        let saved = try await owner.preparedFileState(packageID: h.packageID, pairID: other.intent().pairID)
        #expect(saved.phase == "retiring")
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await h.open()
        try await cold.retirePreparedFiles(saved)
        try await survivor.require(h, cold)
        #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<SharedMediaAllocationRecord>()) == 4)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: [false, true], [false, true])
    func heldLateAcquisitionReopensAndReleasesOnlyItsReservation(holdSaveFails: Bool, otherPackage: Bool) async throws {
        let h = try Harness(), owner = try await h.open(), first = try await h.acquire(owner)
        let ready = try await owner.qualifyPreparedFiles(original: first, recipe: Self.recipe), survivor = try Survivor(h, ready)
        let request = try await owner.prepareOriginal(packageID: otherPackage ? UUID() : h.packageID,
            draftGeneration: otherPackage ? UUID() : h.draft, ordinal: otherPackage ? 0 : 1, kind: .picker)
        if holdSaveFails { try owner.setAcquisitionFault { if $0 == .beforeHeldSave { throw Fault.injected } } }
        await #expect(throws: (any Error).self) { try await owner.acquireOriginal(request) { throw Fault.injected } }
        try owner.setAcquisitionFault(nil)
        let held = try h.state()
        #expect(held.phase == (otherPackage ? "draftOwned" : holdSaveFails ? "acquiring" : "needsAttention"))
        if holdSaveFails {
            // An uncertain held save keeps the owner's settlement barrier shut.
            // Its saved ready assertion cannot bypass that barrier for deletion.
            await #expect(throws: SharedMediaStorageFailure.closed) { try await owner.preparedFileState(packageID: h.packageID) }
            await #expect(throws: SharedMediaStorageFailure.closed) { try await owner.retirePreparedFiles(ready) }
            try survivor.requireBytes(h)
        } else {
            let beforeRetirement = try await owner.preparedFileState(packageID: h.packageID, pairID: ready.intent().pairID)
            await #expect(throws: SharedMediaStorageFailure.closed) { try await owner.retirePreparedFiles(beforeRetirement) }
            try await survivor.require(h, owner)
        }
        #expect(try h.state() == held)
        #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<SharedMediaAllocationRecord>()) == 4)
        await #expect(throws: (any Error).self) { try await owner.reservePreparation(original: first, recipe: Self.recipe) }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await h.open()
        try await survivor.require(h, cold)
        let heldAfterReopen = try h.state()
        let current = try await cold.preparedFileState(packageID: h.packageID, pairID: ready.intent().pairID)
        await #expect(throws: SharedMediaStorageFailure.closed) { try await cold.retirePreparedFiles(current) }
        #expect(try h.state() == heldAfterReopen)
        try await cold.abandonPendingAcquisition(request)
        try await survivor.require(h, cold)
        #expect(try h.state().phase == "draftOwned")
        #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<SharedMediaAllocationRecord>()) == 3)
        let settled = try await cold.preparedFileState(packageID: h.packageID, pairID: ready.intent().pairID)
        try await cold.retirePreparedFiles(settled)
        #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<SharedMediaDerivativePairRecord>()) == 0)
        #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<SharedMediaAllocationRecord>()) == 1)
        #expect(try Data(contentsOf: h.file(first)) == h.bytes)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test func secondPlanExcludesUnrelatedFreshMutationsButNotRecovery() async throws {
        let h = try Harness(), owner = try await h.open(), first = try await h.acquire(owner), second = try await h.acquire(owner, ordinal: 1)
        let share = try await owner.prepareShare(first, packageID: UUID(), draftGeneration: UUID())
        let foreign = try await owner.share(share)
        let metadata = try await owner.prepareMetadata(packageID: foreign.packageID, draftGeneration: foreign.draftGeneration,
            contexts: [.init(freeText: "later")], presentation: nil)
        let acquisition = try await owner.prepareOriginal(packageID: foreign.packageID, draftGeneration: foreign.draftGeneration, ordinal: 1, kind: .picker)
        let ready = try await owner.qualifyPreparedFiles(original: first, recipe: Self.recipe), survivor = try Survivor(h, ready)
        let output = try await owner.qualifyPhotoPreparation(original: second, recipe: Self.recipe, savePlan: true)
        let plan = try #require(try await owner.plannedPreparation(packageID: h.packageID, pairID: output.intent.pairID))
        let before = try h.state()
        await #expect(throws: (any Error).self) { try await owner.saveMetadata(metadata) }
        await #expect(throws: (any Error).self) { try await owner.prepareShare(foreign, packageID: UUID(), draftGeneration: UUID()) }
        await #expect(throws: (any Error).self) { try await owner.prepareRemoval(foreign) }
        let data = h.bytes
        await #expect(throws: (any Error).self) { try await owner.acquireOriginal(acquisition) { data } }
        #expect(try h.state() == before)
        try await survivor.require(h, owner)
        try await owner.abandonPlannedPreparation(plan)
        let next = try await owner.reservePreparation(original: foreign, recipe: Self.recipe)
        try await owner.abandonPreparation(next)
        try await survivor.require(h, owner)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func secondAttemptCapacityDenialDoesNotConsumeSurvivorOrDraft() async throws {
        let h = try Harness(), owner = try await h.open(), first = try await h.acquire(owner), second = try await h.acquire(owner, ordinal: 1)
        let ready = try await owner.qualifyPreparedFiles(original: first, recipe: Self.recipe), survivor = try Survivor(h, ready)
        let before = try h.state()
        try owner.setPreparationFault(nil, availableBytes: 0)
        await #expect(throws: (any Error).self) { try await owner.qualifyPreparedFiles(original: second, recipe: Self.recipe) }
        #expect(try h.state() == before)
        #expect(try await owner.activePreparation(packageID: h.packageID) == nil)
        try await survivor.require(h, owner)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func maximumEscapedTextRejectsOversizedSecondAttemptBeforeProcessing() async throws {
        let h = try Harness(), owner = try await h.open(), first = try await h.acquire(owner), second = try await h.acquire(owner, ordinal: 1)
        let contexts = (0..<4).map { _ in ObservationContext(freeText: String(repeating: "\u{0001}", count: 8_000)) }
        let edit = try await owner.prepareMetadata(packageID: h.packageID, draftGeneration: h.draft, contexts: contexts)
        _ = try await owner.saveMetadata(edit)
        let ready = try await owner.qualifyPreparedFiles(original: first, recipe: Self.recipe), survivor = try Survivor(h, ready)
        let before = try h.state()
        await #expect(throws: (any Error).self) { try await owner.reservePreparation(original: second, recipe: Self.recipe) }
        #expect(try h.state() == before)
        #expect(try await owner.activePreparation(packageID: h.packageID) == nil)
        #expect(try SharedMediaNativeDraftEnvelope.decode(h.state().envelope).contexts == contexts)
        try await survivor.require(h, owner)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    private func secondPairID(_ h: Harness, excluding: UUID) throws -> UUID {
        let rows = try ModelContext(h.container).fetch(FetchDescriptor<SharedMediaDerivativePairRecord>())
        return try #require(rows.first { $0.id != excluding }).id
    }
    @MainActor
    private struct Survivor {
        let state: SharedMediaNativePairFileState
        let bytes: [Data]
        init(_ h: Harness, _ state: SharedMediaNativePairFileState) throws {
            self.state = state
            bytes = try state.work.map { try Data(contentsOf: Self.path(h, state, $0.id)) }
        }
        func require(_ h: Harness, _ owner: SharedMediaNativeOriginalOwner) async throws {
            let current = try await owner.preparedFileState(packageID: state.plan.packageID, pairID: state.intent().pairID)
            #expect(current.phase == "ready" && current.plan.intent == state.plan.intent)
            #expect(current.work == state.work && current.publishedRevision == state.publishedRevision)
            try requireBytes(h)
        }
        func requireBytes(_ h: Harness) throws {
            #expect(try state.work.map { try Data(contentsOf: Self.path(h, state, $0.id)) } == bytes)
            #expect(try Data(contentsOf: h.file(state.intent().preparation.original.reference)) == h.bytes)
        }
        private static func path(_ h: Harness, _ state: SharedMediaNativePairFileState, _ id: UUID) throws -> URL {
            h.base.appendingPathComponent("photo/PhotoPreparation/" + (try state.file(id).token))
        }
    }
}
