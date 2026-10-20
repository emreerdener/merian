import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Native app exact paired-file retirement", .serialized)
@MainActor
struct SharedMediaNativeAppPairRetirementTests {
    typealias Store = SharedMediaNativeAppMetadataTests.Store
    private static let recipe = SharedMediaNativePreparationRecipe(format: .stillImage, isPro: false,
        cropDisplaySize: nil, quarterTurns: 0, scale: 1, offsetX: 0, offsetY: 0)

    @Test(arguments: ["ready", "absent", "empty", "short", "missing", "mixed"])
    func coldRetirementReleasesOnlyExactOutputLiabilities(_ mode: String) async throws {
        let (h, before) = try await fixture(mode), owner = try await reopen(h)
        let intent = try before.intent(), original = try Data(contentsOf: path(h, intent.preparation.original.token))
        try rejectFresh(owner)
        try await owner.retireAppPhotoPair(packageID: h.packageID, pairID: intent.pairID)
        try released(h, before)
        #expect(try Data(contentsOf: path(h, intent.preparation.original.token)) == original)
        await #expect(throws: (any Error).self) { try await owner.retireAppPhotoPair(packageID: h.packageID, pairID: intent.pairID) }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func preservesReceivingPackageAndItsExactConsumer() async throws {
        let (h, before) = try await fixture("ready", receiving: true), consumer = try consumers(h), owner = try await reopen(h)
        try await owner.retireAppPhotoPair(packageID: h.packageID, pairID: before.intent().pairID)
        try released(h, before); #expect(try consumers(h) == consumer)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func removingOnePairPreservesAnotherOriginalAndReadyPair() async throws {
        let (h, first) = try await fixture("ready"), owner = try await reopen(h)
        let request = try await owner.prepareAppOriginal(packageID: h.packageID, draftGeneration: h.draft, ordinal: 1, kind: .picker)
        let data = PhotoPreparationTestHarness.image(), acquired = try await owner.acquireAppOriginal(request) { data }
        let original = PhotoOriginalReference(ownerID: h.ownerID, packageID: h.packageID, referenceID: request.referenceID,
            assetID: request.assetID, assetGeneration: request.assetGeneration, draftGeneration: h.draft, referenceRevision: acquired.referenceRevision)
        let second = try await owner.prepareAndDeliverAppPhoto(original: original, recipe: Self.recipe), secondID = try second.intent().pairID
        let secondFiles = try [second.intent().preparation.original.file, second.file(second.intent().ai.id), second.file(second.intent().display.id)]
        let retained = try secondFiles.map { try Data(contentsOf: path(h, $0.token)) }
        try rejectFresh(owner)
        try await owner.retireAppPhotoPair(packageID: h.packageID, pairID: first.intent().pairID)
        let after = try state(h, pairID: secondID)
        #expect(after.phase == "ready" && after.work == second.work && after.plan.intent == second.plan.intent)
        #expect(try secondFiles.map { try Data(contentsOf: path(h, $0.token)) } == retained)
        #expect(try Data(contentsOf: path(h, first.intent().preparation.original.token)) == data)
        let firstIntent = try first.intent()
        #expect(after.allocatedBytes == second.allocatedBytes - firstIntent.ai.byteCount - firstIntent.display.byteCount)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: [SharedMediaNativePreparationBoundary.beforeFileRetire, .afterFileRetire, .beforeFileRelease, .afterFileRelease])
    func saveBoundariesRetainClosureUntilExactRelease(_ point: SharedMediaNativePreparationBoundary) async throws {
        let (h, before) = try await fixture("ready"), owner = try await reopen(h), id = try before.intent().pairID
        var reached = false
        try owner.setPreparationFault { if $0 == point { reached = true; throw SharedMediaStorageFailure.unavailable } }
        if point == .afterFileRetire || point == .afterFileRelease {
            try await owner.retireAppPhotoPair(packageID: h.packageID, pairID: id); try released(h, before)
        } else {
            await #expect(throws: (any Error).self) { try await owner.retireAppPhotoPair(packageID: h.packageID, pairID: id) }
            let held = try state(h)
            #expect(held.phase == (point == .beforeFileRetire ? "ready" : "retiring"))
            #expect(held.allocatedBytes == before.allocatedBytes)
        }
        #expect(reached); #expect(await owner.invalidateAndAwaitForAccountTransition())
        if point == .beforeFileRetire || point == .beforeFileRelease {
            let cold = try await reopen(h); try rejectFresh(cold)
            try await cold.retireAppPhotoPair(packageID: h.packageID, pairID: id); try released(h, before)
            #expect(await cold.invalidateAndAwaitForAccountTransition())
        }
    }

    @Test(arguments: [SharedMediaNativePreparationBoundary.afterFileRetire, .afterFileRelease])
    func readbackLossCannotGrantUnlinkOrRepeatCommittedRelease(_ point: SharedMediaNativePreparationBoundary) async throws {
        let (h, before) = try await fixture("ready"), owner = try await reopen(h), id = try before.intent().pairID
        var saved = false
        try owner.setPreparationFault {
            if $0 == point { saved = true }
            if saved && $0 == .beforeReadback { throw SharedMediaStorageFailure.unavailable }
        }
        await #expect(throws: (any Error).self) { try await owner.retireAppPhotoPair(packageID: h.packageID, pairID: id) }
        #expect(saved)
        if point == .afterFileRetire {
            #expect(try state(h).phase == "retiring")
            for work in before.work { #expect(FileManager.default.fileExists(atPath: path(h, try before.file(work.id).token).path)) }
        } else { try released(h, before) }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await reopen(h); try rejectFresh(cold)
        if point == .afterFileRelease {
            let called = ImageFocusEngineTests.Signal()
            try await cold.setAcquisitionEntryPause { if $0 == .releasePair { await called.open() } }
            await #expect(throws: (any Error).self) { try await cold.retireAppPhotoPair(packageID: h.packageID, pairID: id) }
            #expect(!(await called.isOpen))
        } else {
            try await cold.retireAppPhotoPair(packageID: h.packageID, pairID: id); try released(h, before)
        }
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: [1, 2])
    func interruptedUnlinkRetainsClosureAndColdReconciles(_ count: Int) async throws {
        let (h, before) = try await fixture("ready"), owner = try await reopen(h)
        let seen = UnlinkCounter(failAt: count)
        try await owner.setAppPairFileFault { if $0 == .afterUnlink { try seen.unlink() } }
        await #expect(throws: (any Error).self) { try await owner.retireAppPhotoPair(packageID: h.packageID, pairID: before.intent().pairID) }
        let held = try state(h)
        #expect(held.phase == "retiring" && held.allocatedBytes == before.allocatedBytes)
        #expect(held.work.allSatisfy { $0.closure != nil && $0.retirementID != nil })
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await reopen(h); try rejectFresh(cold)
        try await cold.retireAppPhotoPair(packageID: h.packageID, pairID: before.intent().pairID); try released(h, before)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["retire-output", "retire-member", "release-partial", "release-parent", "release-member"])
    func finalSealsRejectPhysicalAndMetadataDrift(_ kind: String) async throws {
        let (h, before) = try await fixture("ready"), owner = try await reopen(h)
        let releasing = kind.hasPrefix("release"), point: SharedMediaNativePreparationBoundary = releasing ? .beforeFileRelease : .beforeFileRetire
        var reached = false
        try owner.setPreparationFault { boundary in
            guard boundary == point else { return }; reached = true
            let url = path(h, try before.file(before.intent().ai.id).token)
            if kind.hasSuffix("member") {
                let c = h.context(), id = h.packageID
                let member = try #require(try c.fetch(FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == id })).first)
                member.revision += 1; try c.save()
            } else if kind.hasSuffix("parent") {
                let parent = url.deletingLastPathComponent()
                try FileManager.default.moveItem(at: parent, to: parent.appendingPathExtension("held"))
                try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
            } else if releasing { try Data().write(to: URL(fileURLWithPath: url.path + ".partial")) }
            else { let data = try Data(contentsOf: url); try FileManager.default.removeItem(at: url); try data.write(to: url) }
        }
        await #expect(throws: (any Error).self) { try await owner.retireAppPhotoPair(packageID: h.packageID, pairID: before.intent().pairID) }
        #expect(reached)
        let packageID = h.packageID
        let pair = try #require(try h.context().fetch(FetchDescriptor<SharedMediaDerivativePairRecord>(predicate: #Predicate { $0.packageID == packageID })).first)
        #expect(pair.phaseRaw == (releasing ? "retiring" : "ready"))
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func additionalReferenceLiabilityBlocksRetirement() async throws {
        let (h, before) = try await fixture("ready"), owner = try await reopen(h)
        let c = h.context(), asset = try before.intent().ai.assetID
        let count = try #require(try c.fetch(FetchDescriptor<SharedMediaAssetReferenceCountRecord>(predicate: #Predicate { $0.id == asset })).first)
        count.liveCount = 2; try c.save()
        await #expect(throws: (any Error).self) { try await owner.retireAppPhotoPair(packageID: h.packageID, pairID: before.intent().pairID) }
        for work in before.work { #expect(FileManager.default.fileExists(atPath: path(h, try before.file(work.id).token).path)) }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func cancellationAtReleaseEntryRetainsBothFilesAndClosure() async throws {
        let (h, before) = try await fixture("ready"), owner = try await reopen(h)
        let entered = ImageFocusEngineTests.Signal(), release = ImageFocusEngineTests.Signal(), ended = ImageFocusEngineTests.Signal()
        try await owner.setAcquisitionEntryPause { point in
            guard point == .releasePair else { return }; await entered.open(); await release.wait()
        }
        let operation = Task {
            do { try await owner.retireAppPhotoPair(packageID: h.packageID, pairID: before.intent().pairID); await ended.open(); await entered.open() }
            catch { await ended.open(); await entered.open(); throw error }
        }
        await entered.wait(); #expect(!(await ended.isOpen)); operation.cancel(); await release.open()
        await #expect(throws: (any Error).self) { try await operation.value }
        #expect(try state(h).phase == "retiring")
        for work in before.work { #expect(FileManager.default.fileExists(atPath: path(h, try before.file(work.id).token).path)) }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    private func fixture(_ mode: String, receiving: Bool = false) async throws -> (Store, SharedMediaNativePairFileState) {
        let h = try Store(receiving: receiving)
        let owner: SharedMediaNativeOriginalOwner
        if receiving { owner = try await h.openWithReceivingConsumer().0 } else { owner = try await h.open() }
        let request = try await owner.prepareAppOriginal(packageID: h.packageID, draftGeneration: h.draft, ordinal: 0, kind: .picker)
        let data = PhotoPreparationTestHarness.image(), acquired = try await owner.acquireAppOriginal(request) { data }
        let original = PhotoOriginalReference(ownerID: h.ownerID, packageID: h.packageID, referenceID: request.referenceID,
            assetID: request.assetID, assetGeneration: request.assetGeneration, draftGeneration: h.draft, referenceRevision: acquired.referenceRevision)
        if ["short", "missing"].contains(mode) {
            try await owner.setAppPairFileFault { if $0 == .duringWrite { throw SharedMediaStorageFailure.unavailable } }
        } else if mode != "ready" {
            var identities = 0
            try owner.setPreparationFault {
                if $0 == .beforeFileIdentity { identities += 1; if mode != "mixed" || identities == 2 { throw SharedMediaStorageFailure.unavailable } }
            }
        }
        if mode == "ready" { _ = try await owner.prepareAndDeliverAppPhoto(original: original, recipe: Self.recipe) }
        else { await #expect(throws: (any Error).self) { _ = try await owner.prepareAndDeliverAppPhoto(original: original, recipe: Self.recipe) } }
        let saved = try state(h), file = path(h, try saved.file(saved.intent().ai.id).token)
        let partial = URL(fileURLWithPath: file.path + ".partial")
        if mode == "short" { let handle = try FileHandle(forWritingTo: partial); try handle.truncate(atOffset: 1); try handle.close() }
        if mode == "missing" || mode == "absent" { try FileManager.default.removeItem(at: partial) }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        return (h, saved)
    }
    private func released(_ h: Store, _ before: SharedMediaNativePairFileState) throws {
        let c = h.context(), intent = try before.intent(), id = intent.pairID, packageID = h.packageID
        #expect(try c.fetchCount(FetchDescriptor<SharedMediaDerivativePairRecord>(predicate: #Predicate { $0.id == id })) == 0)
        let package = try #require(try c.fetch(FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == packageID })).first)
        #expect(package.phaseRaw == "draftOwned")
        let completedBytes = try before.work.filter { $0.finalIdentity != nil }.reduce(Int64(0)) { try SharedMediaStoragePolicy.add($0, before.selected($1.id).1.byteCount) }
        #expect(package.allocatedByteCount == before.allocatedBytes - completedBytes)
        for input in [intent.ai, intent.display] {
            let asset = input.assetID, work = input.id, lease = input.leaseID
            #expect(try c.fetchCount(FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.id == asset })) == 0)
            #expect(try c.fetchCount(FetchDescriptor<SharedMediaDerivativeWorkRecord>(predicate: #Predicate { $0.id == work })) == 0)
            #expect(try c.fetchCount(FetchDescriptor<PhotoPreparationLease>(predicate: #Predicate { $0.id == lease })) == 0)
            let url = path(h, try before.file(work).token)
            #expect(!FileManager.default.fileExists(atPath: url.path) && !FileManager.default.fileExists(atPath: url.path + ".partial"))
        }
        let inventoryID = h.inventoryID
        let inventory = try #require(try c.fetch(FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID })).first)
        _ = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: c, inventory: inventory, ownerID: h.ownerID, format: .appV2)
    }
    private func rejectFresh(_ owner: SharedMediaNativeOriginalOwner) throws {
        try owner.setPreparationFault { if [.beforeSave, .beforePairSave, .beforeFileReserve, .beforeFileIdentity, .beforeFileCompletion, .beforeFilePublish].contains($0) { throw SharedMediaStorageFailure.closed } }
    }
    private func path(_ h: Store, _ token: String) -> URL { h.parent.appendingPathComponent("photo/PhotoPreparation").appendingPathComponent(token) }
    private func consumers(_ h: Store) throws -> [SharedMediaNativeAppMetadataFacts.Consumer] { try h.context().fetch(FetchDescriptor<SharedMediaConsumerRecord>()).map { .init($0) } }
    private func state(_ h: Store, pairID: UUID? = nil) throws -> SharedMediaNativePairFileState {
        let c = h.context(), id = h.packageID, inventoryID = h.inventoryID
        let inventory = try #require(try c.fetch(FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID })).first)
        let package = try #require(try c.fetch(FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == id })).first)
        let member = try #require(try c.fetch(FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == id })).first)
        return try SharedMediaNativePairFileGraph.state(context: c, inventory: inventory, package: package, member: member, pairID: pairID)
    }
    private func reopen(_ h: Store) async throws -> SharedMediaNativeOriginalOwner {
        let owner = try SharedMediaNativeOriginalOwner.appDispatch(account: PhotoOriginalPreparationOwner.syntheticAccount(ownerID: h.ownerID, runtime: h.runtime), drain: .init())
        _ = try await owner.openApp(container: h.container, parent: h.parent, inventoryID: h.inventoryID); return owner
    }
    private final class UnlinkCounter: @unchecked Sendable {
        private let lock = NSLock(), failAt: Int
        private var count = 0
        init(failAt: Int) { self.failAt = failAt }
        func unlink() throws {
            lock.lock(); defer { lock.unlock() }; count += 1
            if count == failAt { throw SharedMediaStorageFailure.unavailable }
        }
    }
}
