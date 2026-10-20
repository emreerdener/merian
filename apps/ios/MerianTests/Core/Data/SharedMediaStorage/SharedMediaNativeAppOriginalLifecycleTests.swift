import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Native app shared original lifecycle", .serialized)
@MainActor
struct SharedMediaNativeAppOriginalLifecycleTests {
    typealias Store = SharedMediaNativeAppMetadataTests.Store

    @Test func sharingKeepsOnePhysicalOriginalAndExactSource() async throws {
        let h = try Store(), owner = try await h.open(), source = try await acquire(h, owner)
        let sourcePackage = try SharedMediaNativeAppMetadataFacts.Package(h.package())
        let share = try await owner.prepareAppOriginalShare(source, packageID: UUID(), draftGeneration: UUID())
        let destination = try await owner.shareAppOriginal(share)
        #expect(try await owner.shareAppOriginal(share) == destination)
        #expect(try SharedMediaNativeAppMetadataFacts.Package(h.package()) == sourcePackage)
        #expect(try h.context().fetchCount(FetchDescriptor<PhotoPreparationAsset>()) == 1)
        #expect(try count(h, source.assetID).liveCount == 2)
        #expect(try h.package(destination.packageID).allocatedByteCount == share.original.byteCount)
        #expect(try h.package(h.ordinaryID).supportingContextData == Data("ordinary-draft".utf8))
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }
    @Test func removalPreservesSurvivingShareThenColdReleasesFinalOriginal() async throws {
        let h = try Store(), owner = try await h.open(), source = try await acquire(h, owner)
        let share = try await owner.prepareAppOriginalShare(source, packageID: UUID(), draftGeneration: UUID())
        let destination = try await owner.shareAppOriginal(share), file = path(h, share.original.fileToken)
        let bytes = try Data(contentsOf: file)
        let first = try await owner.prepareAppOriginalRemoval(source)
        try await owner.removeAppOriginal(first); try await owner.removeAppOriginal(first)
        #expect(try count(h, source.assetID).liveCount == 1)
        #expect(try Data(contentsOf: file) == bytes)
        #expect(try h.package().allocatedByteCount == 0)
        let last = try await owner.prepareAppOriginalRemoval(destination)
        try await owner.removeAppOriginal(last)
        #expect(try count(h, source.assetID).liveCount == 0)
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await reopen(h)
        try await cold.removeAppOriginal(last)
        try await cold.recoverAppOriginalRetirements()
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(try h.package(destination.packageID).allocatedByteCount == 0)
        #expect(try h.context().fetchCount(FetchDescriptor<PhotoPreparationAsset>()) == 0)
        let receipt = try #require(try h.context().fetch(FetchDescriptor<SharedMediaAcquisitionReceiptRecord>()).first)
        #expect(receipt.phaseRaw == "terminal" && receipt.requestData == nil && receipt.resultData == nil)
        await #expect(throws: (any Error).self) { try await cold.removeAppOriginal(last) }
        try await cold.recoverAppOriginalRetirements()
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }
    @Test func coldReleaseUsesCurrentInventoryAfterUnrelatedProgress() async throws {
        let h = try Store(), owner = try await h.open(), source = try await acquire(h, owner)
        let removal = try await owner.prepareAppOriginalRemoval(source)
        try await owner.removeAppOriginal(removal)
        let retained = try accounting(h, source.assetID)
        let other = try await acquire(h, owner, packageID: UUID())
        let survivor = try accounting(h, other.assetID)
        #expect(survivor.inventoryRevision > retained.inventoryRevision)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await reopen(h)
        try await cold.recoverAppOriginalRetirements()
        #expect(!FileManager.default.fileExists(atPath: path(h, retained.fileToken).path))
        #expect(FileManager.default.fileExists(atPath: path(h, survivor.fileToken).path))
        #expect(try count(h, other.assetID).liveCount == 1)
        #expect(try h.package(other.packageID).allocatedByteCount == survivor.byteCount)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }
    @Test(arguments: ["counter", "identity", "reference", "pair", "work", "dirty"])
    func unrelatedAcquisitionRequiresAnExactSavedRetirement(_ fault: String) async throws {
        let h = try Store(), owner = try await h.open(), source = try await acquire(h, owner)
        let removal = try await owner.prepareAppOriginalRemoval(source)
        try await owner.removeAppOriginal(removal)
        let c = h.context(), assetID = source.assetID, referenceID = source.referenceID
        let inventory = try #require(try c.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first)
        #expect(throws: (any Error).self) { try SharedMediaNativePreparationGraph.requireIdleFiles(c, scopedInventory: inventory) }
        try SharedMediaNativePreparationGraph.requireIdleFiles(c, scopedInventory: inventory, allowSavedOriginalRetirements: true)
        switch fault {
        case "counter": try count(h, assetID, context: c).retirementID = nil
        case "identity":
            let row = try #require(try c.fetch(FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.id == assetID })).first)
            row.physicalIdentity = "invalid-retirement"
        case "reference":
            let row = try #require(try c.fetch(FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.id == referenceID })).first)
            row.isLive = true
        case "pair":
            c.insert(SharedMediaDerivativePairRecord(id: UUID(), nonce: UUID(), inventoryID: h.inventoryID,
                inventoryGeneration: inventory.generation, expectedInventoryRevision: inventory.revision,
                ownerID: h.ownerID, packageID: h.packageID, draftGeneration: h.draft,
                originalReferenceID: referenceID, originalReferenceRevision: source.referenceRevision,
                originalAssetID: assetID, originalAssetGeneration: source.assetGeneration, ordinal: 0,
                expectedPackageRevision: removal.package.revision, aiWorkID: UUID(), displayWorkID: UUID()))
        case "work":
            c.insert(SharedMediaDerivativeWorkRecord(id: UUID(), pairID: UUID(), roleRaw: "aiInput", assetID: assetID,
                assetGeneration: source.assetGeneration, referenceID: UUID(), leaseID: UUID(), writerEpoch: UUID(),
                byteCount: 1, sha256: String(repeating: "a", count: 64), contentType: "public.jpeg"))
        default: inventory.revision += 1
        }
        if fault != "dirty" { try c.save() }
        #expect(throws: (any Error).self) {
            try SharedMediaNativePreparationGraph.requireIdleFiles(c, scopedInventory: inventory, allowSavedOriginalRetirements: true)
        }
        c.rollback()
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }
    @Test func removalPreservesContextsAndOtherPresentationExactly() async throws {
        let h = try Store(), owner = try await h.open(), source = try await acquire(h, owner)
        let next = try await owner.prepareAppOriginal(packageID: h.packageID,
            draftGeneration: h.draft, ordinal: 1, kind: .picker)
        let bytes = PhotoPreparationTestHarness.image()
        _ = try await owner.acquireAppOriginal(next) { bytes }
        func presentation(_ id: UUID, turn: Int) -> PhotoPreparationImagePresentation {
            .init(referenceID: id, addedAt: Date(timeIntervalSince1970: 100), isFromGallery: true,
                cropQuarterTurns: turn, cropScale: 1.5, cropOffsetX: 0.1, cropOffsetY: 0.2,
                focus: nil, latitude: nil, longitude: nil, locationName: nil,
                weatherCondition: nil, weatherTemperature: nil, captureDate: nil)
        }
        let contexts: [ObservationContext] = [.init(freeText: "Observed under a leaf"), .init(freeText: "Preserve both notes")]
        let retained = presentation(next.referenceID, turn: 2)
        let metadata = try await owner.prepareAppMetadata(packageID: h.packageID, draftGeneration: h.draft,
            contexts: contexts, presentation: [presentation(source.referenceID, turn: 1), retained])
        _ = try await owner.saveAppMetadata(metadata)
        let removal = try await owner.prepareAppOriginalRemoval(source)
        try await owner.removeAppOriginal(removal)
        let actual = try PhotoPreparationPolicy.decodeDraft(h.package().supportingContextData)
        #expect(actual.contexts == contexts)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let actualBytes = try encoder.encode(actual.presentation), expectedBytes = try encoder.encode([retained])
        #expect(actualBytes == expectedBytes)
        #expect(try count(h, next.assetID).liveCount == 1)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }
    @Test func v1RemovalValidatesContentWithoutReencodingHistoricalBytes() async throws {
        let h = try Store(), owner = try await h.open(), source = try await acquire(h, owner)
        let request = try await owner.prepareAppOriginalRemoval(source)
        guard case .remove(let value) = request.action else { Issue.record("Expected removal"); return }
        func replacing(_ envelope: Data) -> SharedMediaNativeAppOriginalRequest {
            let removal = SharedMediaNativeRemovalRequest(source: value.source, inventoryID: value.inventoryID,
                inventoryGeneration: value.inventoryGeneration, inventoryRevision: value.inventoryRevision,
                packageRevision: value.packageRevision, membershipRevision: value.membershipRevision,
                membershipBytes: value.membershipBytes, previousEnvelope: value.previousEnvelope,
                envelope: envelope, liveCount: value.liveCount, countRevision: value.countRevision, retirementID: value.retirementID)
            return .init(profile: request.profile, source: request.source, package: request.package,
                member: request.member, original: request.original, ordinal: request.ordinal, action: .remove(removal))
        }
        // Deliberately different whitespace/key order must not rewrite or invalidate V1 content.
        let expectedBytes = Data("{ \"presentation\": [], \"contexts\": [], \"version\": 1 }".utf8)
        let equivalent = replacing(expectedBytes)
        try SharedMediaNativeAppOriginalPoststate.validateRequest(equivalent)
        let changed = replacing(try PhotoPreparationPolicy.encodeDraft(contexts: [.init(freeText: "Changed")]))
        #expect(throws: (any Error).self) { try SharedMediaNativeAppOriginalPoststate.validateRequest(changed) }
        try await owner.removeAppOriginal(equivalent)
        #expect(try h.package().supportingContextData == expectedBytes)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }
    @Test func replayAllowsOnlyUnrelatedProgress() async throws {
        let h = try Store(), owner = try await h.open(), source = try await acquire(h, owner)
        let request = try await owner.prepareAppOriginalShare(source, packageID: UUID(), draftGeneration: UUID())
        let shared = try await owner.shareAppOriginal(request)
        let unrelated = try await acquire(h, owner, packageID: UUID())
        #expect(try await owner.shareAppOriginal(request) == shared)
        let removal = try await owner.prepareAppOriginalRemoval(source)
        try await owner.removeAppOriginal(removal)
        let extra = try await owner.prepareAppOriginal(packageID: unrelated.packageID, draftGeneration: unrelated.draftGeneration, ordinal: 1, kind: .picker)
        let bytes = PhotoPreparationTestHarness.image(); _ = try await owner.acquireAppOriginal(extra) { bytes }
        try await owner.removeAppOriginal(removal)
        let next = try await owner.prepareAppOriginalShare(shared, packageID: UUID(), draftGeneration: UUID())
        _ = try await owner.shareAppOriginal(next)
        await #expect(throws: (any Error).self) { try await owner.removeAppOriginal(removal) }
        await #expect(throws: (any Error).self) { _ = try await owner.shareAppOriginal(request) }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }
    @Test(arguments: [false, true], [SharedMediaNativeLifecycleBoundary.beforeSave, .afterSave])
    func logicalSaveFaultsAreAtomic(_ removal: Bool, _ point: SharedMediaNativeLifecycleBoundary) async throws {
        let h = try Store(), owner = try await h.open(), source = try await acquire(h, owner)
        let request = removal ? try await owner.prepareAppOriginalRemoval(source)
            : try await owner.prepareAppOriginalShare(source, packageID: UUID(), draftGeneration: UUID())
        try owner.setLifecycleFault { if $0 == point { throw SharedMediaStorageFailure.unavailable } }
        if point == .beforeSave {
            await #expect(throws: (any Error).self) { try await apply(owner, request) }
            #expect(try count(h, source.assetID).liveCount == 1)
        } else { try await apply(owner, request) }
        try owner.setLifecycleFault(nil); try await apply(owner, request)
        #expect(try count(h, source.assetID).liveCount == (removal ? 0 : 2))
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }
    @Test(arguments: [false, true])
    func acknowledgementLossRecoversExactLocalSuccessor(_ removal: Bool) async throws {
        let h = try Store(), owner = try await h.open(), source = try await acquire(h, owner)
        let request = removal ? try await owner.prepareAppOriginalRemoval(source)
            : try await owner.prepareAppOriginalShare(source, packageID: UUID(), draftGeneration: UUID())
        var lost = false
        try owner.setLifecycleFault { point in
            if point == .afterSave { lost = true }
            if lost && point == .beforeReadback { throw SharedMediaStorageFailure.unavailable }
        }
        await #expect(throws: (any Error).self) { try await apply(owner, request) }
        try owner.setLifecycleFault(nil)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await reopen(h); try await apply(cold, request)
        #expect(try count(h, source.assetID).liveCount == (removal ? 0 : 2))
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }
    @Test(arguments: [SharedMediaPhotoReleaseBoundary.beforeUnlink, .afterUnlink, .beforeSync, .afterSync])
    func physicalInterruptionKeepsSavedRetirement(_ point: SharedMediaPhotoReleaseBoundary) async throws {
        let h = try Store(), owner = try await h.open(), source = try await acquire(h, owner)
        let removal = try await owner.prepareAppOriginalRemoval(source)
        try await owner.removeAppOriginal(removal)
        let original = try accounting(h, source.assetID)
        try await owner.setAppOriginalReleaseFault { if $0 == point { throw SharedMediaStorageFailure.unavailable } }
        await #expect(throws: (any Error).self) { try await owner.recoverAppOriginalRetirements() }
        #expect(try accounting(h, source.assetID) == original)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await reopen(h); try await cold.recoverAppOriginalRetirements()
        #expect(!FileManager.default.fileExists(atPath: path(h, original.fileToken).path))
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }
    @Test(arguments: [SharedMediaNativeLifecycleBoundary.beforeReleaseSave, .afterReleaseSave])
    func releaseSaveFaultRetainsOrAcknowledgesExactAccounting(_ point: SharedMediaNativeLifecycleBoundary) async throws {
        let h = try Store(), owner = try await h.open(), source = try await acquire(h, owner)
        let request = try await owner.prepareAppOriginalRemoval(source); try await owner.removeAppOriginal(request)
        try owner.setLifecycleFault { if $0 == point { throw SharedMediaStorageFailure.unavailable } }
        if point == .beforeReleaseSave {
            await #expect(throws: (any Error).self) { try await owner.recoverAppOriginalRetirements() }
            #expect(try h.context().fetchCount(FetchDescriptor<PhotoPreparationAsset>()) == 1)
        } else { try await owner.recoverAppOriginalRetirements() }
        try owner.setLifecycleFault(nil); try await owner.recoverAppOriginalRetirements()
        #expect(try h.context().fetchCount(FetchDescriptor<PhotoPreparationAsset>()) == 0)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }
    @Test(arguments: ["replace", "late"])
    func changedFileCannotReleaseAccounting(_ kind: String) async throws {
        let h = try Store(), owner = try await h.open(), source = try await acquire(h, owner)
        let request = try await owner.prepareAppOriginalRemoval(source); try await owner.removeAppOriginal(request)
        let file = path(h, request.original.fileToken), bytes = PhotoPreparationTestHarness.image()
        if kind == "replace" { try bytes.write(to: file, options: .atomic) }
        else { try owner.setLifecycleFault { if $0 == .beforeReleaseSave { try bytes.write(to: file) } } }
        await #expect(throws: (any Error).self) { try await owner.recoverAppOriginalRetirements() }
        #expect(try h.context().fetchCount(FetchDescriptor<PhotoPreparationAsset>()) == 1)
        #expect(FileManager.default.fileExists(atPath: file.path))
        _ = await owner.invalidateAndAwaitForAccountTransition()
    }
    @Test(arguments: [false, true])
    func changedOriginalAccountingBlocksAtSaveBoundary(_ target: Bool) async throws {
        let h = try Store(), owner = try await h.open(), source = try await acquire(h, owner)
        let other = try await acquire(h, owner, packageID: UUID())
        let request = try await owner.prepareAppOriginalRemoval(source)
        let id = target ? source.assetID : other.assetID
        try owner.setLifecycleFault { point in
            if point == .beforeSave { let c = h.context(); try count(h, id, context: c).revision += 1; try c.save() }
        }
        await #expect(throws: (any Error).self) { try await owner.removeAppOriginal(request) }
        #expect(try count(h, source.assetID).liveCount == 1)
        #expect(FileManager.default.fileExists(atPath: path(h, request.original.fileToken).path))
        _ = await owner.invalidateAndAwaitForAccountTransition()
    }
    @Test func preparedPairRequiresExplicitRetirementAndOtherConsumerSurvives() async throws {
        let h = try Store(receiving: true), (owner, consumerID) = try await h.openWithReceivingConsumer()
        let consumer = SharedMediaNativeAppMetadataFacts.Consumer(try #require(try SharedMediaConsumerLookup.one(h.context(), id: consumerID)))
        let source = try await acquire(h, owner)
        let recipe = SharedMediaNativePreparationRecipe(format: .stillImage, isPro: false,
            cropDisplaySize: nil, quarterTurns: 0, scale: 1, offsetX: 0, offsetY: 0)
        let prepared = try await owner.prepareAndDeliverAppPhoto(original: source, recipe: recipe)
        await #expect(throws: (any Error).self) { _ = try await owner.prepareAppOriginalRemoval(source) }
        let share = try await owner.prepareAppOriginalShare(source, packageID: UUID(), draftGeneration: UUID())
        let destination = try await owner.shareAppOriginal(share)
        let removal = try await owner.prepareAppOriginalRemoval(destination); try await owner.removeAppOriginal(removal)
        let currentPlan = try await owner.savedAppPlan(packageID: source.packageID, pairID: prepared.intent().pairID)
        let previous = prepared.plan
        #expect(currentPlan.inventoryRevision > previous.inventoryRevision)
        let rebased = SharedMediaNativePairPlan(intent: previous.intent, writerEpoch: previous.writerEpoch,
            inventoryID: previous.inventoryID, inventoryGeneration: previous.inventoryGeneration,
            inventoryRevision: currentPlan.inventoryRevision, packageID: previous.packageID,
            draftGeneration: previous.draftGeneration, packageRevision: previous.packageRevision,
            envelope: previous.envelope, membershipRevision: previous.membershipRevision, membership: previous.membership)
        #expect(currentPlan == rebased)
        try await owner.retireAppPhotoPair(packageID: source.packageID, pairID: prepared.intent().pairID)
        let final = try await owner.prepareAppOriginalRemoval(source); try await owner.removeAppOriginal(final)
        try await owner.recoverAppOriginalRetirements()
        let current = SharedMediaNativeAppMetadataFacts.Consumer(try #require(try SharedMediaConsumerLookup.one(h.context(), id: consumerID)))
        #expect(consumer == current)
        #expect(try h.package(h.ordinaryID).supportingContextData == Data("ordinary-draft".utf8))
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }
    @Test func missingOriginalCannotCreateNewShare() async throws {
        let h = try Store(), owner = try await h.open(), source = try await acquire(h, owner)
        let request = try await owner.prepareAppOriginalShare(source, packageID: UUID(), draftGeneration: UUID())
        try FileManager.default.removeItem(at: path(h, request.original.fileToken))
        await #expect(throws: (any Error).self) { _ = try await owner.shareAppOriginal(request) }
        #expect(try count(h, source.assetID).liveCount == 1)
        #expect(try h.context().fetchCount(FetchDescriptor<SharedMediaPendingMembershipRecord>()) == 1)
        _ = await owner.invalidateAndAwaitForAccountTransition()
    }
    @Test func cancellationBeforeUnlinkPreservesOriginal() async throws {
        let h = try Store(), owner = try await h.open(), source = try await acquire(h, owner)
        let request = try await owner.prepareAppOriginalRemoval(source); try await owner.removeAppOriginal(request)
        try await owner.setAppOriginalReleaseFault { point in
            if point == .beforeUnlink { withUnsafeCurrentTask { $0?.cancel() } }
        }
        let task = Task { @MainActor in try await owner.recoverAppOriginalRetirements() }
        await #expect(throws: (any Error).self) { try await task.value }
        #expect(FileManager.default.fileExists(atPath: path(h, request.original.fileToken).path))
        #expect(try count(h, source.assetID).liveCount == 0)
        _ = await owner.invalidateAndAwaitForAccountTransition()
    }
    private func acquire(_ h: Store, _ owner: SharedMediaNativeOriginalOwner, packageID: UUID? = nil) async throws -> PhotoOriginalReference {
        let request = try await owner.prepareAppOriginal(packageID: packageID ?? h.packageID,
            draftGeneration: packageID == nil ? h.draft : UUID(), ordinal: 0, kind: .picker)
        let bytes = PhotoPreparationTestHarness.image(); let result = try await owner.acquireAppOriginal(request) { bytes }
        return .init(ownerID: request.ownerID, packageID: request.packageID, referenceID: request.referenceID,
            assetID: request.assetID, assetGeneration: request.assetGeneration, draftGeneration: request.draftGeneration, referenceRevision: result.referenceRevision)
    }
    private func apply(_ owner: SharedMediaNativeOriginalOwner, _ r: SharedMediaNativeAppOriginalRequest) async throws {
        switch r.action {
        case .share: _ = try await owner.shareAppOriginal(r)
        case .remove: try await owner.removeAppOriginal(r)
        }
    }
    private func reopen(_ h: Store) async throws -> SharedMediaNativeOriginalOwner {
        let owner = try SharedMediaNativeOriginalOwner.appDispatch(account: PhotoOriginalPreparationOwner.syntheticAccount(ownerID: h.ownerID, runtime: h.runtime), drain: .init())
        _ = try await owner.openApp(container: h.container, parent: h.parent, inventoryID: h.inventoryID); return owner
    }
    private func path(_ h: Store, _ token: String) -> URL { h.parent.appendingPathComponent("photo/PhotoPreparation").appendingPathComponent(token) }
    private func count(_ h: Store, _ id: UUID, context: ModelContext? = nil) throws -> SharedMediaAssetReferenceCountRecord {
        try SharedMediaNativeAppOriginalRows.one(context ?? h.context(), FetchDescriptor<SharedMediaAssetReferenceCountRecord>(predicate: #Predicate { $0.id == id }))
    }
    private func accounting(_ h: Store, _ id: UUID) throws -> SharedMediaNativeOriginalAccounting.Snapshot {
        try SharedMediaNativeOriginalAccounting.audit(assetID: id, inventoryID: h.inventoryID, context: h.context())
    }
}
