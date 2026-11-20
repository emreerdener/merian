import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Native app exact paired-file recovery", .serialized)
@MainActor
struct SharedMediaNativeAppPairRecoveryTests {
    typealias Store = SharedMediaNativeAppMetadataTests.Store
    private static let recipe = SharedMediaNativePreparationRecipe(format: .stillImage, isPro: false,
        cropDisplaySize: nil, quarterTurns: 0, scale: 1, offsetX: 0, offsetY: 0)

    @Test(arguments: [false, true])
    func coldPublicationPreservesBytesAndNeverProcesses(_ receiving: Bool) async throws {
        let (h, before) = try await interrupted(.beforeFilePublish, receiving: receiving)
        let baseline = try bytes(h, before), consumer = try consumers(h), oldEpoch = before.plan.writerEpoch
        let cold = try await reopen(h)
        var observedEpoch: UUID?
        try cold.setPreparationFault({ try rejectFresh($0) }, fileEpochObserved: { observedEpoch = $0 })
        let result = try await cold.recoverAppPhotoPair(packageID: h.packageID, pairID: before.intent().pairID)
        #expect(result.phase == "ready" && result.plan.writerEpoch == oldEpoch)
        #expect(observedEpoch != nil && observedEpoch != oldEpoch)
        #expect(try bytes(h, result) == baseline)
        #expect(try consumers(h) == consumer)
        #expect(try await cold.recoverAppPhotoPair(packageID: h.packageID, pairID: before.intent().pairID) == result)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: [false, true])
    func coldBoundOutputCompletionNeverCreatesMissingSibling(_ partial: Bool) async throws {
        let (h, before) = try await interrupted(partial ? nil : .beforeFileCompletion)
        let intent = try before.intent(), oldEpoch = before.plan.writerEpoch
        let first = try path(h, before.file(intent.ai.id).token)
        let inputURL = partial ? URL(fileURLWithPath: first.path + ".partial") : first
        let expected = try Data(contentsOf: inputURL)
        let cold = try await reopen(h); try prohibitFreshWork(cold)
        let result = try await cold.recoverAppPhotoPair(packageID: h.packageID, pairID: intent.pairID)
        #expect(result.phase == "writing" && result.plan.writerEpoch == oldEpoch)
        #expect(try result.selected(intent.ai.id).0.phase == "completed")
        #expect(try result.selected(intent.display.id).0.phase == "reserved")
        #expect(try Data(contentsOf: first) == expected)
        #expect(!FileManager.default.fileExists(atPath: first.path + ".partial"))
        let sibling = try path(h, result.file(intent.display.id).token)
        #expect(!FileManager.default.fileExists(atPath: sibling.path))
        #expect(!FileManager.default.fileExists(atPath: sibling.path + ".partial"))
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["short", "missing", "extra"])
    func unavailableOrConflictingSavedBytesStayHeld(_ kind: String) async throws {
        let (h, before) = try await interrupted(nil), intent = try before.intent()
        let final = try path(h, before.file(intent.ai.id).token), partial = URL(fileURLWithPath: final.path + ".partial")
        if kind == "missing" { try FileManager.default.removeItem(at: partial) }
        else if kind == "short" {
            let handle = try FileHandle(forWritingTo: partial); try handle.truncate(atOffset: 0); try handle.close()
        } else { try Data(contentsOf: partial).write(to: final) }
        let cold = try await reopen(h); try prohibitFreshWork(cold)
        if kind == "extra" {
            await #expect(throws: (any Error).self) { _ = try await cold.recoverAppPhotoPair(packageID: h.packageID, pairID: intent.pairID) }
        } else {
            #expect(try await cold.recoverAppPhotoPair(packageID: h.packageID, pairID: intent.pairID) == before)
        }
        #expect(try state(h) == before)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: [SharedMediaNativePreparationBoundary.afterFileCompletion, .afterFilePublish])
    func exactAcknowledgementRecoversOneSave(_ point: SharedMediaNativePreparationBoundary) async throws {
        let (h, before) = try await interrupted(point == .afterFileCompletion ? .beforeFileCompletion : .beforeFilePublish)
        let cold = try await reopen(h); var saves = 0
        try cold.setPreparationFault { boundary in
            try rejectFresh(boundary)
            if boundary == point { saves += 1; throw SharedMediaStorageFailure.unavailable }
        }
        let result = try await cold.recoverAppPhotoPair(packageID: h.packageID, pairID: before.intent().pairID)
        #expect(saves == 1 && result.plan.packageRevision == before.plan.packageRevision + 1)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: [SharedMediaNativePreparationBoundary.afterFileCompletion, .afterFilePublish])
    func lostReadbackStopsAndColdRetryOnlyReadsPersistedState(_ point: SharedMediaNativePreparationBoundary) async throws {
        let (h, before) = try await interrupted(point == .afterFileCompletion ? .beforeFileCompletion : .beforeFilePublish)
        let cold = try await reopen(h); var saved = false
        try cold.setPreparationFault { boundary in
            try rejectFresh(boundary)
            if boundary == point { saved = true }
            if saved && boundary == .beforeReadback { throw SharedMediaStorageFailure.unavailable }
        }
        await #expect(throws: (any Error).self) { _ = try await cold.recoverAppPhotoPair(packageID: h.packageID, pairID: before.intent().pairID) }
        #expect(saved)
        let persisted = try state(h)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
        let again = try await reopen(h); try prohibitFreshWork(again)
        #expect(try await again.recoverAppPhotoPair(packageID: h.packageID, pairID: before.intent().pairID) == persisted)
        #expect(await again.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["original", "output", "parent", "member"])
    func finalRecoverySealRejectsReplacement(_ kind: String) async throws {
        let (h, before) = try await interrupted(.beforeFilePublish), cold = try await reopen(h)
        var reached = false
        try cold.setPreparationFault { boundary in
            try rejectFresh(boundary)
            guard boundary == .beforeFilePublish else { return }; reached = true
            let intent = try before.intent()
            let url = try path(h, kind == "original" ? intent.preparation.original.token : before.file(intent.ai.id).token)
            if kind == "member" {
                let context = h.context(), id = h.packageID
                let row = try #require(try context.fetch(FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == id })).first)
                row.revision += 1; try context.save()
            } else if kind == "parent" {
                let parent = url.deletingLastPathComponent()
                try FileManager.default.moveItem(at: parent, to: parent.appendingPathExtension("held"))
                try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
            } else {
                let data = try Data(contentsOf: url); try FileManager.default.removeItem(at: url); try data.write(to: url)
            }
        }
        await #expect(throws: (any Error).self) { _ = try await cold.recoverAppPhotoPair(packageID: h.packageID, pairID: before.intent().pairID) }
        #expect(reached)
        #expect(try state(h).phase == "writing")
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test func cancellationAtRecoveryEntryCannotRenamePartial() async throws {
        let (h, before) = try await interrupted(nil), cold = try await reopen(h)
        let entered = ImageFocusEngineTests.Signal(), release = ImageFocusEngineTests.Signal(), ended = ImageFocusEngineTests.Signal()
        try await cold.setAcquisitionEntryPause { point in
            guard point == .recoverPair else { return }; await entered.open(); await release.wait()
        }
        let operation = Task {
            do { let result = try await cold.recoverAppPhotoPair(packageID: h.packageID, pairID: before.intent().pairID); await ended.open(); await entered.open(); return result }
            catch { await ended.open(); await entered.open(); throw error }
        }
        await entered.wait(); #expect(!(await ended.isOpen))
        operation.cancel(); await release.open()
        await #expect(throws: (any Error).self) { _ = try await operation.value }
        let final = try path(h, before.file(before.intent().ai.id).token)
        #expect(!FileManager.default.fileExists(atPath: final.path))
        #expect(FileManager.default.fileExists(atPath: final.path + ".partial"))
        #expect(try state(h) == before)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    private func interrupted(_ boundary: SharedMediaNativePreparationBoundary?, receiving: Bool = false) async throws -> (Store, SharedMediaNativePairFileState) {
        let h = try Store(receiving: receiving)
        let owner: SharedMediaNativeOriginalOwner
        if receiving { owner = try await h.openWithReceivingConsumer().0 } else { owner = try await h.open() }
        let request = try await owner.prepareAppOriginal(packageID: h.packageID, draftGeneration: h.draft, ordinal: 0, kind: .picker)
        let data = PhotoPreparationTestHarness.image(), acquired = try await owner.acquireAppOriginal(request) { data }
        let original = PhotoOriginalReference(ownerID: h.ownerID, packageID: h.packageID, referenceID: request.referenceID,
            assetID: request.assetID, assetGeneration: request.assetGeneration, draftGeneration: h.draft, referenceRevision: acquired.referenceRevision)
        if let boundary { try owner.setPreparationFault { if $0 == boundary { throw SharedMediaStorageFailure.unavailable } } }
        else { try await owner.setAppPairFileFault { if $0 == .duringWrite { throw SharedMediaStorageFailure.unavailable } } }
        await #expect(throws: (any Error).self) { _ = try await owner.prepareAndDeliverAppPhoto(original: original, recipe: Self.recipe) }
        let saved = try state(h)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        return (h, saved)
    }
    private func prohibitFreshWork(_ owner: SharedMediaNativeOriginalOwner) throws { try owner.setPreparationFault { try rejectFresh($0) } }
    private func rejectFresh(_ point: SharedMediaNativePreparationBoundary) throws {
        if [.beforeSave, .beforePairSave, .beforeFileReserve, .beforeFileIdentity].contains(point) { throw SharedMediaStorageFailure.closed }
    }
    private func path(_ h: Store, _ token: String) -> URL { h.parent.appendingPathComponent("photo/PhotoPreparation").appendingPathComponent(token) }
    private func bytes(_ h: Store, _ state: SharedMediaNativePairFileState) throws -> [Data] {
        let intent = try state.intent()
        return try [intent.preparation.original.file, state.file(intent.ai.id), state.file(intent.display.id)].map { try Data(contentsOf: path(h, $0.token)) }
    }
    private func consumers(_ h: Store) throws -> [SharedMediaNativeAppMetadataFacts.Consumer] {
        try h.context().fetch(FetchDescriptor<SharedMediaConsumerRecord>()).map { .init($0) }
    }
    private func state(_ h: Store) throws -> SharedMediaNativePairFileState {
        let c = h.context(), id = h.packageID, inventoryID = h.inventoryID
        let inventory = try #require(try c.fetch(FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID })).first)
        let package = try #require(try c.fetch(FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == id })).first)
        let member = try #require(try c.fetch(FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == id })).first)
        return try SharedMediaNativePairFileGraph.state(context: c, inventory: inventory, package: package, member: member)
    }
    private func reopen(_ h: Store) async throws -> SharedMediaNativeOriginalOwner {
        let owner = try SharedMediaNativeOriginalOwner.appDispatch(account: PhotoOriginalPreparationOwner.syntheticAccount(ownerID: h.ownerID, runtime: h.runtime), drain: .init())
        _ = try await owner.openApp(container: h.container, parent: h.parent, inventoryID: h.inventoryID); return owner
    }
}
