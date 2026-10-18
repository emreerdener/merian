import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Native sharing removal and recovery", .serialized)
@MainActor
struct SharedMediaNativeLifecycleTests {
    @Test(arguments: [true, false])
    func bothRemovalOrdersPreserveSurvivorAndLastDraft(_ originFirst: Bool) async throws {
        let h = try Harness(), owner = try await h.open()
        let (intent, original) = try await h.acquire(owner)
        let edit = try await owner.prepareMetadata(packageID: h.packageID, draftGeneration: h.draft, contexts: [.init(freeText: "durable synthetic draft")])
        _ = try await owner.saveMetadata(edit)
        let request = try await owner.prepareShare(original, packageID: UUID(), draftGeneration: UUID())
        let shared = try await owner.share(request), receipt = try h.receipt(intent)
        #expect(try await owner.share(request) == shared)
        #expect(try h.count().liveCount == 2)
        let first = originFirst ? original : shared, last = originFirst ? shared : original
        let removeFirst = try await owner.prepareRemoval(first)
        try await owner.remove(removeFirst)
        #expect(try h.count().liveCount == 1)
        #expect(try Data(contentsOf: h.file(intent)) == h.bytes)
        #expect(try h.receipt(intent) == receipt)
        #expect(try h.package(first.packageID).allocatedByteCount == 0)
        let removeLast = try await owner.prepareRemoval(last)
        try await owner.remove(removeLast)
        #expect(!FileManager.default.fileExists(atPath: h.file(intent).path))
        #expect(try h.rows(SharedMediaAllocationRecord.self) == 0)
        #expect(try h.rows(SharedMediaAssetReferenceCountRecord.self) == 0)
        #expect(try h.rows(PhotoPreparationReference.self) == 0)
        #expect(try h.rows(PhotoPreparationRecord.self) == 2)
        #expect(try PhotoPreparationPolicy.decodeDraft(h.package(h.packageID).supportingContextData).contexts == [.init(freeText: "durable synthetic draft")])
        #expect(try h.receipt(intent).phase == "terminal")
        #expect(!(try await owner.snapshot().requiresRecovery))
        await #expect(throws: (any Error).self) { try await owner.share(request) }
        await #expect(throws: (any Error).self) { try await owner.remove(removeLast) }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let reopened = try await h.open()
        let fresh = try await reopened.prepareOriginal(packageID: h.packageID, draftGeneration: h.draft, ordinal: 0, kind: .picker)
        let bytes = h.bytes; _ = try await reopened.acquireOriginal(fresh) { bytes }
        #expect(try PhotoPreparationPolicy.decodeDraft(h.package(h.packageID).supportingContextData).contexts == [.init(freeText: "durable synthetic draft")])
        #expect(await reopened.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: [SharedMediaNativeLifecycleBoundary.beforeSave, .afterSave])
    func sharingLostAcknowledgementAndRestart(_ point: SharedMediaNativeLifecycleBoundary) async throws {
        let h = try Harness(), owner = try await h.open(); let (_, original) = try await h.acquire(owner)
        let request = try await owner.prepareShare(original, packageID: UUID(), draftGeneration: UUID())
        try owner.setLifecycleFault { if $0 == point { throw Fault.injected } }
        if point == .beforeSave { await #expect(throws: Fault.self) { try await owner.share(request) } }
        else { #expect(try await owner.share(request) == request.destination()) }
        try owner.setLifecycleFault(nil)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let reopened = try await h.open()
        #expect(try await reopened.share(request) == request.destination())
        #expect(try h.count().liveCount == 2)
        #expect(await reopened.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: [SharedMediaPhotoReleaseBoundary.beforeUnlink, .afterUnlink, .beforeSync, .afterSync])
    func cleanupFailuresKeepChargedIntentAndRecoverAfterRestart(_ point: SharedMediaPhotoReleaseBoundary) async throws {
        let h = try Harness(), owner = try await h.open(); let (intent, original) = try await h.acquire(owner)
        let request = try await owner.prepareRemoval(original)
        try await owner.setReleaseFault { if $0 == point { throw Fault.injected } }
        await #expect(throws: Fault.self) { try await owner.remove(request) }
        #expect(try h.count().liveCount == 0)
        #expect(try h.rows(SharedMediaAllocationRecord.self) == 1)
        #expect(try h.receipt(intent).phase == "completed")
        #expect(try await owner.snapshot().requiresRecovery)
        await #expect(throws: (any Error).self) { try await owner.prepareShare(original, packageID: UUID(), draftGeneration: UUID()) }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let reopened = try await h.open()
        try await reopened.recoverRetirements()
        #expect(try h.rows(SharedMediaAllocationRecord.self) == 0)
        #expect(try h.receipt(intent).phase == "terminal")
        #expect(!FileManager.default.fileExists(atPath: h.file(intent).path))
        #expect(await reopened.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: [SharedMediaNativeLifecycleBoundary.beforeReleaseSave, .afterReleaseSave])
    func releaseSaveAcknowledgementHasExactRecovery(_ point: SharedMediaNativeLifecycleBoundary) async throws {
        let h = try Harness(), owner = try await h.open(); let (intent, original) = try await h.acquire(owner)
        let request = try await owner.prepareRemoval(original)
        try owner.setLifecycleFault { if $0 == point { throw Fault.injected } }
        if point == .beforeReleaseSave {
            await #expect(throws: Fault.self) { try await owner.remove(request) }
            #expect(try h.receipt(intent).phase == "completed")
            #expect(try h.rows(SharedMediaAllocationRecord.self) == 1)
        } else { try await owner.remove(request) }
        try owner.setLifecycleFault(nil)
        try await owner.recoverRetirements()
        #expect(try h.receipt(intent).phase == "terminal")
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func cancellationAfterUnlinkRetainsRecoveryAuthority() async throws {
        let h = try Harness(), owner = try await h.open(); let (intent, original) = try await h.acquire(owner)
        let request = try await owner.prepareRemoval(original)
        try await owner.setReleaseFault { if $0 == .afterUnlink { withUnsafeCurrentTask { $0?.cancel() } } }
        let attempt = Task { try await owner.remove(request) }
        await #expect(throws: (any Error).self) { try await attempt.value }
        #expect(try h.receipt(intent).phase == "completed")
        #expect(try h.rows(SharedMediaAllocationRecord.self) == 1)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let reopened = try await h.open(); try await reopened.recoverRetirements()
        #expect(try h.rows(SharedMediaAllocationRecord.self) == 0)
        #expect(await reopened.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: [true, false])
    func shareVersusFinalRemovalDoesNotRebase(_ shareFirst: Bool) async throws {
        let h = try Harness(), owner = try await h.open(); let (_, original) = try await h.acquire(owner)
        let share = try await owner.prepareShare(original, packageID: UUID(), draftGeneration: UUID())
        let remove = try await owner.prepareRemoval(original)
        if shareFirst {
            _ = try await owner.share(share)
            await #expect(throws: (any Error).self) { try await owner.remove(remove) }
            #expect(try h.count().liveCount == 2)
        } else {
            try await owner.remove(remove)
            await #expect(throws: (any Error).self) { try await owner.share(share) }
            #expect(try h.rows(SharedMediaAssetReferenceCountRecord.self) == 0)
        }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func destinationRemovalNeverResurrectsOnShareReplay() async throws {
        let h = try Harness(), owner = try await h.open(); let (intent, original) = try await h.acquire(owner)
        let request = try await owner.prepareShare(original, packageID: UUID(), draftGeneration: UUID())
        let shared = try await owner.share(request)
        let removal = try await owner.prepareRemoval(shared); try await owner.remove(removal)
        await #expect(throws: (any Error).self) { try await owner.share(request) }
        #expect(try h.count().liveCount == 1)
        #expect(try Data(contentsOf: h.file(intent)) == h.bytes)
        #expect(try h.package(shared.packageID).allocatedByteCount == 0)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func existingDestinationAndForeignHandleAreRejected() async throws {
        let h = try Harness(), owner = try await h.open(); let (_, original) = try await h.acquire(owner)
        await #expect(throws: (any Error).self) { try await owner.prepareShare(original, packageID: h.packageID, draftGeneration: h.draft) }
        let foreign = PhotoOriginalReference(ownerID: UUID(), packageID: original.packageID, referenceID: original.referenceID,
            assetID: original.assetID, assetGeneration: original.assetGeneration, draftGeneration: original.draftGeneration, referenceRevision: original.referenceRevision)
        await #expect(throws: (any Error).self) { try await owner.prepareRemoval(foreign) }
        await #expect(throws: (any Error).self) { try await owner.prepareShare(foreign, packageID: UUID(), draftGeneration: UUID()) }
        #expect(try h.count().liveCount == 1)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func pendingDraftLimitDoesNotCopyPhysicalPhoto() async throws {
        let h = try Harness(), owner = try await h.open(); let (intent, original) = try await h.acquire(owner)
        for _ in 0..<3 { _ = try await owner.share(owner.prepareShare(original, packageID: UUID(), draftGeneration: UUID())) }
        let request = try await owner.prepareShare(original, packageID: UUID(), draftGeneration: UUID())
        await #expect(throws: (any Error).self) { try await owner.share(request) }
        #expect(try h.rows(PhotoPreparationRecord.self) == 4)
        #expect(try h.rows(SharedMediaAllocationRecord.self) == 1)
        #expect(try h.count().liveCount == 4)
        #expect(try Data(contentsOf: h.file(intent)) == h.bytes)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func pendingAcquisitionIsNeverReplayedByRetirementRecovery() async throws {
        let h = try Harness(), owner = try await h.open()
        let request = try await owner.prepareOriginal(packageID: h.packageID, draftGeneration: h.draft, ordinal: 0, kind: .picker)
        await #expect(throws: Fault.self) { try await owner.acquireOriginal(request) { throw Fault.injected } }
        try await owner.recoverRetirements()
        #expect(try h.rows(PhotoPreparationLease.self) == 1)
        #expect(try await owner.snapshot().requiresRecovery)
        await #expect(throws: (any Error).self) { try await owner.acquireOriginal(request) { Issue.record("Repeated a cold loader"); return Data() } }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func removalPreservesTextAndDropsOnlyRemovedPresentation() async throws {
        let h = try Harness(), owner = try await h.open(); let (_, original) = try await h.acquire(owner)
        let photo = PhotoPreparationImagePresentation(referenceID: original.referenceID, addedAt: Date(timeIntervalSince1970: 1),
            isFromGallery: true, cropQuarterTurns: 0, cropScale: 1, cropOffsetX: 0, cropOffsetY: 0,
            focus: nil, latitude: nil, longitude: nil, locationName: nil, weatherCondition: nil, weatherTemperature: nil, captureDate: nil)
        let edit = try await owner.prepareMetadata(packageID: h.packageID, draftGeneration: h.draft,
            contexts: [.init(freeText: "keep this draft")], presentation: [photo])
        _ = try await owner.saveMetadata(edit)
        let removal = try await owner.prepareRemoval(original); try await owner.remove(removal)
        let saved = try PhotoPreparationPolicy.decodeDraft(h.package(h.packageID).supportingContextData)
        #expect(saved.contexts == [.init(freeText: "keep this draft")] && saved.presentation.isEmpty)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func retainedSourceSurvivesPendingShareRemoval() async throws {
        let h = try Harness(), owner = try await h.open(); let (intent, original) = try await h.acquire(owner)
        let context = ModelContext(h.container), id = h.packageID
        let package = try #require(context.fetch(FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == id })).first)
        let member = try #require(context.fetch(FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == id })).first)
        package.accountingTierRaw = "retained"; context.delete(member); try context.save()
        let share = try await owner.prepareShare(original, packageID: UUID(), draftGeneration: UUID())
        let destination = try await owner.share(share)
        let removal = try await owner.prepareRemoval(destination); try await owner.remove(removal)
        #expect(try h.count().liveCount == 1)
        #expect(try Data(contentsOf: h.file(intent)) == h.bytes)
        #expect(try h.package(h.packageID).accountingTierRaw == "retained")
        await #expect(throws: (any Error).self) { try await owner.prepareRemoval(original) }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func replacementAtUnlinkBoundaryIsNeverDeleted() async throws {
        let h = try Harness(), owner = try await h.open(); let (intent, original) = try await h.acquire(owner)
        let removal = try await owner.prepareRemoval(original), url = h.file(intent), bytes = h.bytes
        try await owner.setReleaseFault { point in if point == .beforeUnlink { try bytes.write(to: url, options: .atomic) } }
        await #expect(throws: (any Error).self) { try await owner.remove(removal) }
        #expect(try Data(contentsOf: url) == h.bytes)
        #expect(try h.count().liveCount == 0 && h.rows(SharedMediaAllocationRecord.self) == 1)
        #expect(try h.receipt(intent).phase == "completed")
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        await #expect(throws: (any Error).self) { _ = try await h.open() }
    }

    @Test(arguments: [false, true])
    func coherentInterveningMembershipCannotMasqueradeAsAcknowledgement(_ releasing: Bool) async throws {
        let h = try Harness(), owner = try await h.open(); let (_, original) = try await h.acquire(owner)
        let second = try await owner.prepareOriginal(packageID: h.packageID, draftGeneration: h.draft, ordinal: 1, kind: .picker)
        let bytes = h.bytes; _ = try await owner.acquireOriginal(second) { bytes }
        if !releasing { _ = try await owner.share(owner.prepareShare(original, packageID: UUID(), draftGeneration: UUID())) }
        let removal = try await owner.prepareRemoval(original)
        try owner.setLifecycleFault { point in
            if point == (releasing ? .afterReleaseSave : .afterSave) {
                try h.swapReference(second.referenceID)
                throw Fault.injected
            }
        }
        await #expect(throws: Fault.self) { try await owner.remove(removal) }
        try owner.setLifecycleFault(nil)
        #expect(!(try await owner.snapshot().requiresRecovery))
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func recoveryDrainsSuccessiveBoundedDiscoveries() async throws {
        let h = try Harness(), owner = try await h.open(); let (first, _) = try await h.acquire(owner)
        let second = try await owner.prepareOriginal(packageID: h.packageID, draftGeneration: h.draft, ordinal: 1, kind: .picker)
        let bytes = h.bytes; _ = try await owner.acquireOriginal(second) { bytes }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        // Seed two independently saved, exact completed retirements. The normal
        // owner blocks new work once recovery is pending; cold admission must
        // nevertheless settle every valid saved intent, one bounded row at a time.
        try h.seedRetirement(first); try h.seedRetirement(second)
        let reopened = try await h.open(); #expect(try await reopened.snapshot().requiresRecovery)
        try await reopened.recoverRetirements()
        #expect(try h.rows(SharedMediaAllocationRecord.self) == 0)
        #expect(try h.receipt(first).phase == "terminal" && h.receipt(second).phase == "terminal")
        #expect(try h.package(h.packageID).allocatedByteCount == 0)
        #expect(await reopened.invalidateAndAwaitForAccountTransition())
    }

    private enum Fault: Error { case injected }
    private struct Receipt: Equatable { let phase: String, request: Data?, result: Data? }
    @MainActor private struct Harness {
        let base: URL, container: ModelContainer
        let inventoryID = UUID(), ownerID = UUID(), packageID = UUID(), draft = UUID()
        let runtime = AuthRuntimeState(), bytes = PhotoPreparationTestHarness.image()
        init() throws {
            base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("native-lifecycle-" + UUID().uuidString)
            print("NATIVE_LIFECYCLE_FIXTURE " + base.path)
            for name in ["authority", "photo", "inbox", "database"] { try FileManager.default.createDirectory(at: base.appendingPathComponent(name), withIntermediateDirectories: true) }
            let schema = Schema(versionedSchema: CurrentSchema.self)
            container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: base.appendingPathComponent("database/ledger.store"), cloudKitDatabase: .none)])
        }
        func open() async throws -> SharedMediaNativeOriginalOwner {
            let owner = try SharedMediaNativeOriginalOwner.qualification(account: PhotoOriginalPreparationOwner.syntheticAccount(ownerID: ownerID, runtime: runtime), drain: .init())
            _ = try await owner.open(container: container, authorityRoot: base.appendingPathComponent("authority"), photoRoot: base.appendingPathComponent("photo"), inboxRoot: base.appendingPathComponent("inbox"), inventoryID: inventoryID)
            return owner
        }
        func acquire(_ owner: SharedMediaNativeOriginalOwner) async throws -> (SharedMediaAcquisitionIntent, PhotoOriginalReference) {
            let request = try await owner.prepareOriginal(packageID: packageID, draftGeneration: draft, ordinal: 0, kind: .picker)
            let data = bytes; _ = try await owner.acquireOriginal(request) { data }
            return (request, .init(ownerID: ownerID, packageID: packageID, referenceID: request.referenceID,
                assetID: request.assetID, assetGeneration: request.assetGeneration, draftGeneration: draft, referenceRevision: 0))
        }
        func rows<T: PersistentModel>(_ type: T.Type) throws -> Int { try ModelContext(container).fetchCount(FetchDescriptor<T>()) }
        func count() throws -> SharedMediaAssetReferenceCountRecord { try #require(ModelContext(container).fetch(FetchDescriptor<SharedMediaAssetReferenceCountRecord>()).first) }
        func package(_ id: UUID) throws -> PhotoPreparationRecord { try #require(ModelContext(container).fetch(FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == id })).first) }
        func receipt(_ request: SharedMediaAcquisitionIntent) throws -> Receipt {
            let id = request.operationID
            let row = try #require(ModelContext(container).fetch(FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.id == id })).first)
            return .init(phase: row.phaseRaw, request: row.requestData, result: row.resultData)
        }
        func swapReference(_ id: UUID) throws {
            let context = ModelContext(container)
            let old = try #require(context.fetch(FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.id == id })).first)
            let edge = try #require(context.fetch(FetchDescriptor<SharedMediaReferenceRecord>(predicate: #Predicate { $0.id == id })).first)
            let replacement = UUID(), pid = old.packageID
            context.insert(PhotoPreparationReference(id: replacement, packageID: pid, assetID: old.assetID, ownerID: old.ownerID,
                roleRaw: old.roleRaw, ordinal: old.ordinal, revision: old.revision, isLive: true))
            context.insert(SharedMediaReferenceRecord(id: replacement, allocationID: edge.allocationID, accountID: edge.accountID,
                ownerID: replacement.uuidString.lowercased(), roleRaw: edge.roleRaw, stateRaw: "live", revision: edge.revision))
            context.delete(old); context.delete(edge)
            let inventory = try #require(context.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first)
            let member = try #require(context.fetch(FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == pid })).first)
            member.membersData = try SharedMediaPendingGraph.derive(in: context, inventory: inventory).membership(packageID: pid).encoded()
            try context.save()
        }
        func seedRetirement(_ request: SharedMediaAcquisitionIntent) throws {
            let context = ModelContext(container), aid = request.assetID, rid = request.referenceID, op = request.operationID, pid = request.packageID
            let receipt = try #require(context.fetch(FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.id == op })).first)
            guard case .completed(_, let result) = try SharedMediaAcquisitionReceipt.read(receipt) else { throw Fault.injected }
            let inventory = try #require(context.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first)
            let package = try #require(context.fetch(FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == pid })).first)
            let member = try #require(context.fetch(FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == pid })).first)
            let asset = try #require(context.fetch(FetchDescriptor<PhotoPreparationAsset>(predicate: #Predicate { $0.id == aid })).first)
            let allocation = try #require(context.fetch(FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.id == aid })).first)
            let count = try #require(context.fetch(FetchDescriptor<SharedMediaAssetReferenceCountRecord>(predicate: #Predicate { $0.id == aid })).first)
            let ref = try #require(context.fetch(FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.id == rid })).first)
            let edge = try #require(context.fetch(FetchDescriptor<SharedMediaReferenceRecord>(predicate: #Predicate { $0.id == rid })).first)
            let retirement = UUID()
            allocation.stateRaw = SharedMediaNativeRetirementIdentity.allocationState
            allocation.physicalIdentity = try SharedMediaNativeRetirementIdentity(retirementID: retirement, assetID: aid,
                assetGeneration: asset.generation, inventoryID: inventory.id, inventoryGeneration: inventory.generation,
                ownerID: ownerID, proof: result.descriptor).encoded()
            count.liveCount = 0; count.revision += 1; count.retirementID = retirement
            ref.isLive = false; ref.revision += 1; edge.stateRaw = "retired"; edge.revision = ref.revision
            asset.cleanupStateRaw = "retiring"; package.revision += 1; member.revision += 1; inventory.revision += 1
            try context.save()
        }
        func file(_ request: SharedMediaAcquisitionIntent) -> URL { base.appendingPathComponent("photo/PhotoPreparation/" + request.finalToken) }
        // Exact emitted synthetic directories are removed only after test host exit.
    }
}
