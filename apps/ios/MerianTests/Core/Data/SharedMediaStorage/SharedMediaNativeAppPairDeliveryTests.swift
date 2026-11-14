import Foundation
import ImageIO
import SwiftData
import Testing
@testable import Merian

@Suite("Native app paired-file delivery", .serialized)
@MainActor
struct SharedMediaNativeAppPairDeliveryTests {
    typealias Store = SharedMediaNativeAppMetadataTests.Store
    private static let recipe = SharedMediaNativePreparationRecipe(format: .stillImage, isPro: false,
        cropDisplaySize: nil, quarterTurns: 0, scale: 1, offsetX: 0, offsetY: 0)

    @Test(arguments: [false, true], ["ordinary", "manual", "camera"])
    func freshDeliveryRetainsOriginalAndPublishesExactPair(_ receiving: Bool, _ pathKind: String) async throws {
        let h = try Store(receiving: receiving)
        let owner: SharedMediaNativeOriginalOwner
        if receiving { owner = try await h.openWithReceivingConsumer().0 } else { owner = try await h.open() }
        let original = try await acquire(h, owner), baseline = try unrelated(h)
        var planSaves = 0, reserveSaves = 0, partialSaves = 0, completionSaves = 0, publishSaves = 0
        try owner.setPreparationFault { point in
            if point == .beforePairSave { planSaves += 1 }
            if point == .beforeFileReserve { reserveSaves += 1 }
            if point == .beforeFileIdentity { partialSaves += 1 }
            if point == .beforeFileCompletion { completionSaves += 1 }
            if point == .beforeFilePublish { publishSaves += 1 }
        }
        let recipe: SharedMediaNativePreparationRecipe
        switch pathKind {
        case "manual":
            recipe = .init(format: .stillImage, isPro: false, cropDisplaySize: 96,
                quarterTurns: 1, scale: 1.5, offsetX: 3, offsetY: -2)
        case "camera":
            recipe = .init(format: .cameraStill, isPro: true, cropDisplaySize: nil,
                quarterTurns: 0, scale: 1, offsetX: 0, offsetY: 0, cameraVerticalCenter: 0.35)
        default: recipe = Self.recipe
        }
        let state = try await owner.prepareAndDeliverAppPhoto(original: original, recipe: recipe)
        #expect(planSaves == 1 && reserveSaves == 1 && partialSaves == 2 && completionSaves == 2 && publishSaves == 1)
        #expect(state.phase == "ready" && state.publishedRevision == state.plan.packageRevision)
        #expect(state.work.allSatisfy { $0.phase == "completed" && $0.writerState == "closed" })
        let intent = try state.intent()
        #expect(intent.preparation.original.contentType == "public.png")
        #expect(try Data(contentsOf: path(h, intent.preparation.original.token)) == PhotoPreparationTestHarness.image())
        for input in [intent.ai, intent.display] {
            let file = try state.file(input.id), bytes = try Data(contentsOf: path(h, file.token))
            try SharedMediaDerivativeWorkFiles.validate(bytes, input: input)
            let image = try #require(CGImageSourceCreateWithData(bytes as CFData, nil))
            #expect(CGImageSourceGetType(image) as String? == "public.jpeg")
            #expect(input.contentType == "public.jpeg")
            #expect(!FileManager.default.fileExists(atPath: path(h, file.token).path + ".partial"))
            let lease = input.leaseID
            #expect(try h.context().fetchCount(FetchDescriptor<PhotoPreparationLease>(predicate: #Predicate { $0.id == lease })) == 0)
            #expect(try h.context().fetchCount(FetchDescriptor<SharedMediaLeaseRecord>(predicate: #Predicate { $0.id == lease })) == 0)
        }
        #expect(try unrelated(h) == baseline)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await reopen(h)
        #expect(try await cold.savedAppPlan(packageID: h.packageID, pairID: intent.pairID) == state.plan)
        await #expect(throws: (any Error).self) { try await cold.abandonAppPlan(state.plan) }
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: [SharedMediaNativePreparationBoundary.beforeFileReserve, .beforeFileIdentity, .beforeFileCompletion, .beforeFilePublish])
    func failureRetainsLiabilityWithoutProcessingReplay(_ point: SharedMediaNativePreparationBoundary) async throws {
        let h = try Store(), owner = try await h.open(), original = try await acquire(h, owner)
        var planSaves = 0
        try owner.setPreparationFault { boundary in
            if boundary == .beforePairSave { planSaves += 1 }
            if boundary == point { throw SharedMediaStorageFailure.unavailable }
        }
        await #expect(throws: (any Error).self) { _ = try await owner.prepareAndDeliverAppPhoto(original: original, recipe: Self.recipe) }
        let state = try state(h)
        #expect(planSaves == 1)
        #expect(state.phase == (point == .beforeFileReserve ? "planned" : "writing"))
        try owner.setPreparationFault(nil)
        await #expect(throws: (any Error).self) { _ = try await owner.prepareAndDeliverAppPhoto(original: original, recipe: Self.recipe) }
        if point == .beforeFileReserve { try await owner.abandonAppPlan(state.plan) }
        else { await #expect(throws: (any Error).self) { try await owner.abandonAppPlan(state.plan) } }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await reopen(h)
        if point != .beforeFileReserve {
            let recovered = try await cold.savedAppPlan(packageID: h.packageID, pairID: state.intent().pairID)
            #expect(recovered == state.plan)
            await #expect(throws: (any Error).self) { _ = try await cold.prepareAndDeliverAppPhoto(original: original, recipe: Self.recipe) }
        }
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: [SharedMediaNativePreparationBoundary.afterFileReserve, .afterFileIdentity, .afterFileCompletion, .afterFilePublish])
    func exactReadbackResolvesLostSaveAcknowledgement(_ point: SharedMediaNativePreparationBoundary) async throws {
        let h = try Store(), owner = try await h.open(), original = try await acquire(h, owner)
        var plans = 0, hits = 0
        try owner.setPreparationFault { boundary in
            if boundary == .beforePairSave { plans += 1 }
            if boundary == point { hits += 1; throw SharedMediaStorageFailure.unavailable }
        }
        let result = try await owner.prepareAndDeliverAppPhoto(original: original, recipe: Self.recipe)
        #expect(result.phase == "ready" && plans == 1 && hits > 0)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: [SharedMediaNativePreparationBoundary.afterFileReserve, .afterFileIdentity, .afterFileCompletion, .afterFilePublish])
    func readbackLossEndsOperationWithoutAnotherWrite(_ point: SharedMediaNativePreparationBoundary) async throws {
        let h = try Store(), owner = try await h.open(), original = try await acquire(h, owner)
        var saved = false, plans = 0
        try owner.setPreparationFault { boundary in
            if boundary == .beforePairSave { plans += 1 }
            if boundary == point { saved = true }
            if saved && boundary == .beforeReadback { throw SharedMediaStorageFailure.unavailable }
        }
        await #expect(throws: (any Error).self) { _ = try await owner.prepareAndDeliverAppPhoto(original: original, recipe: Self.recipe) }
        #expect(saved && plans == 1)
        let before = try state(h)
        try owner.setPreparationFault(nil)
        #expect(try await owner.savedAppPlan(packageID: h.packageID, pairID: before.intent().pairID) == before.plan)
        #expect(try state(h) == before)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["original", "output", "emptyPartial", "parent", "member"])
    func finalPublishSealRejectsReplacementAndMetadataDrift(_ kind: String) async throws {
        let h = try Store(), owner = try await h.open(), original = try await acquire(h, owner)
        var reached = false
        try owner.setPreparationFault { point in
            guard point == .beforeFilePublish else { return }; reached = true
            let state = try state(h), intent = try state.intent()
            let url = try path(h, kind == "original" ? intent.preparation.original.token : state.file(intent.ai.id).token)
            if kind == "member" {
                let c = h.context(), id = h.packageID
                let row = try #require(try c.fetch(FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == id })).first)
                row.revision += 1; try c.save()
            } else if kind == "emptyPartial" { try Data().write(to: URL(fileURLWithPath: url.path + ".partial")) }
            else if kind == "parent" {
                let parent = url.deletingLastPathComponent()
                try FileManager.default.moveItem(at: parent, to: parent.appendingPathExtension("held"))
                try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
            } else {
                let bytes = try Data(contentsOf: url)
                try FileManager.default.removeItem(at: url); try bytes.write(to: url)
            }
        }
        await #expect(throws: (any Error).self) { _ = try await owner.prepareAndDeliverAppPhoto(original: original, recipe: Self.recipe) }
        #expect(reached)
        let packageID = h.packageID
        let pair = try #require(try h.context().fetch(FetchDescriptor<SharedMediaDerivativePairRecord>(predicate: #Predicate { $0.packageID == packageID })).first)
        #expect(pair.phaseRaw == "writing" && pair.publishedRevision == nil)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func reservationRechecksAvailableSpaceAtFinalBoundary() async throws {
        let h = try Store(), owner = try await h.open(), original = try await acquire(h, owner)
        var reached = false
        try owner.setPreparationFault { point in
            guard point == .beforeFileReserve else { return }; reached = true
            try owner.setPreparationFault(nil, availableBytes: 0)
        }
        await #expect(throws: (any Error).self) { _ = try await owner.prepareAndDeliverAppPhoto(original: original, recipe: Self.recipe) }
        #expect(reached)
        #expect(try state(h).phase == "planned")
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: [SharedMediaInboxHandoffBoundary.afterPartialCreate, .duringWrite, .afterRename])
    func interruptedPhysicalWorkCannotReplayPreparation(_ point: SharedMediaInboxHandoffBoundary) async throws {
        let h = try Store(), owner = try await h.open(), original = try await acquire(h, owner)
        try await owner.setAppPairFileFault { if $0 == point { throw SharedMediaStorageFailure.unavailable } }
        await #expect(throws: (any Error).self) { _ = try await owner.prepareAndDeliverAppPhoto(original: original, recipe: Self.recipe) }
        let before = try state(h)
        #expect(before.phase == "writing" && before.publishedRevision == nil)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await reopen(h)
        #expect(try await cold.savedAppPlan(packageID: h.packageID, pairID: before.intent().pairID) == before.plan)
        await #expect(throws: (any Error).self) { _ = try await cold.prepareAndDeliverAppPhoto(original: original, recipe: Self.recipe) }
        await #expect(throws: (any Error).self) { try await cold.abandonAppPlan(before.plan) }
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test func cancellationAtPairEntryCreatesNoPartial() async throws {
        let h = try Store(), owner = try await h.open(), original = try await acquire(h, owner)
        let entered = ImageFocusEngineTests.Signal(), release = ImageFocusEngineTests.Signal(), ended = ImageFocusEngineTests.Signal()
        try await owner.setAcquisitionEntryPause { point in
            guard point == .beginPair else { return }
            await entered.open(); await release.wait()
        }
        let operation = Task {
            do { let result = try await owner.prepareAndDeliverAppPhoto(original: original, recipe: Self.recipe); await ended.open(); await entered.open(); return result }
            catch { await ended.open(); await entered.open(); throw error }
        }
        await entered.wait()
        #expect(!(await ended.isOpen))
        operation.cancel(); await release.open()
        await #expect(throws: (any Error).self) { _ = try await operation.value }
        let retained = try state(h)
        #expect(retained.phase == "writing")
        #expect(retained.work.allSatisfy { $0.phase == "reserved" && $0.device == nil && $0.inode == nil })
        for work in retained.work {
            let url = try path(h, retained.file(work.id).token)
            #expect(!FileManager.default.fileExists(atPath: url.path))
            #expect(!FileManager.default.fileExists(atPath: url.path + ".partial"))
        }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func cancellationDuringWriteRetainsOwnerUntilIOSettles() async throws {
        let h = try Store(), owner = try await h.open(), original = try await acquire(h, owner)
        let entered = ImageFocusEngineTests.Signal(), ended = ImageFocusEngineTests.Signal()
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        try await owner.setAppPairFileFault { point in
            guard point == .duringWrite else { return }
            Task { await entered.open() }; release.wait()
        }
        let operation = Task {
            do { let result = try await owner.prepareAndDeliverAppPhoto(original: original, recipe: Self.recipe); await ended.open(); return result }
            catch { await entered.open(); await ended.open(); throw error }
        }
        await entered.wait()
        #expect(!(await ended.isOpen))
        operation.cancel()
        let transition = Task { await owner.invalidateAndAwaitForAccountTransition() }
        release.signal()
        await #expect(throws: (any Error).self) { _ = try await operation.value }
        #expect(await transition.value)
        #expect(try state(h).phase == "writing")
    }

    private func acquire(_ h: Store, _ owner: SharedMediaNativeOriginalOwner) async throws -> PhotoOriginalReference {
        let request = try await owner.prepareAppOriginal(packageID: h.packageID, draftGeneration: h.draft, ordinal: 0, kind: .picker)
        let bytes = PhotoPreparationTestHarness.image(), result = try await owner.acquireAppOriginal(request) { bytes }
        return .init(ownerID: h.ownerID, packageID: h.packageID, referenceID: request.referenceID,
            assetID: request.assetID, assetGeneration: request.assetGeneration, draftGeneration: h.draft, referenceRevision: result.referenceRevision)
    }
    private func path(_ h: Store, _ token: String) -> URL { h.parent.appendingPathComponent("photo/PhotoPreparation").appendingPathComponent(token) }
    private func state(_ h: Store) throws -> SharedMediaNativePairFileState {
        let c = h.context(), id = h.packageID, inventoryID = h.inventoryID
        let inventory = try #require(try c.fetch(FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID })).first)
        let package = try #require(try c.fetch(FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == id })).first)
        let member = try #require(try c.fetch(FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == id })).first)
        return try SharedMediaNativePairFileGraph.state(context: c, inventory: inventory, package: package, member: member)
    }
    private func unrelated(_ h: Store) throws -> [String: Data] {
        let c = h.context(), id = h.packageID
        var result = ["ordinary": try h.package(h.ordinaryID).supportingContextData]
        for row in try c.fetch(FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id != id })) { result["member:" + row.id.uuidString] = row.membersData }
        for row in try c.fetch(FetchDescriptor<SharedMediaConsumerRecord>()) { result["consumer:" + row.id.uuidString] = row.cohortData }
        return result
    }
    private func reopen(_ h: Store) async throws -> SharedMediaNativeOriginalOwner {
        let owner = try SharedMediaNativeOriginalOwner.appDispatch(account: PhotoOriginalPreparationOwner.syntheticAccount(ownerID: h.ownerID, runtime: h.runtime), drain: .init())
        _ = try await owner.openApp(container: h.container, parent: h.parent, inventoryID: h.inventoryID); return owner
    }
}
