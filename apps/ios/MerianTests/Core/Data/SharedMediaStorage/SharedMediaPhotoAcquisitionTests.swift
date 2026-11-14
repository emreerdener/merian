import Darwin
import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Isolated shared photo acquisition", .serialized)
@MainActor
struct SharedMediaPhotoAcquisitionTests {
    enum Fault: Error, Equatable { case injected }

    @Test func originalsAndPairedOwnershipSurviveReopen() async throws {
        let h = try Harness(), bytes = PhotoPreparationTestHarness.image(), package = UUID(), generation = UUID()
        var owner: SharedMediaPhotoAcquisitionOwner? = try h.owner()
        let first = try await owner!.acquire(packageID: package, draftGeneration: generation, ordinal: 0, load: { bytes })
        let second = try await owner!.acquire(packageID: package, draftGeneration: generation, ordinal: 1, load: { bytes })
        #expect(try await owner!.originalData(first) == bytes)
        let context = ModelContext(h.container)
        let allocations = try context.fetch(FetchDescriptor<SharedMediaAllocationRecord>())
        #expect(allocations.count == 2)
        #expect(allocations.allSatisfy { $0.stateRaw == "p1Materialized" && $0.reservedBytes == 0 && $0.materializedBytes == bytes.count })
        #expect(try context.fetchCount(FetchDescriptor<PhotoPreparationLease>()) == 0)
        #expect(try context.fetch(FetchDescriptor<SharedMediaLeaseRecord>()).allSatisfy { $0.stateRaw == "closed" && $0.purposeRaw == "p1AcquireV1" })
        let edges = try context.fetch(FetchDescriptor<SharedMediaReferenceRecord>())
        #expect(Set(edges.map(\.id)) == Set([first.referenceID, second.referenceID]))
        #expect(edges.allSatisfy { $0.ownerID == $0.id.uuidString.lowercased() })
        owner = nil
        let reopened = try h.owner()
        let recovery = try await reopened.recover()
        #expect(!recovery.requiresRecovery && Set(recovery.originals) == Set([first, second]))
        #expect(try await reopened.originalData(second) == bytes)
        #expect(try SharedMediaStorageRepository.hasLiabilities(in: ModelContext(h.container)))
    }

    @Test(arguments: [SharedMediaPhotoBoundary.afterReservationSave, .afterCompletionSave])
    func lostAcknowledgementUsesExactReadbackWithoutRepeatingProvider(_ boundary: SharedMediaPhotoBoundary) async throws {
        let h = try Harness(), owner = try h.owner(), calls = Calls(), bytes = PhotoPreparationTestHarness.image()
        owner.setFault { if $0 == boundary { throw Fault.injected } }
        let handle = try await owner.acquire(packageID: UUID(), draftGeneration: UUID(), ordinal: 0, load: { await calls.hit(); return bytes })
        #expect(await calls.count == 1)
        #expect(try await owner.originalData(handle) == bytes)
    }

    @Test func failedReservationNeverCallsProviderOrCreatesAPhysicalAllocation() async throws {
        let h = try Harness(), owner = try h.owner(), calls = Calls()
        owner.setFault { if $0 == .beforeReservationSave { throw Fault.injected } }
        await #expect(throws: (any Error).self) {
            try await owner.acquire(packageID: UUID(), draftGeneration: UUID(), ordinal: 0, load: { await calls.hit(); return Data() })
        }
        #expect(await calls.count == 0)
        let context = ModelContext(h.container)
        #expect(try context.fetchCount(FetchDescriptor<PhotoPreparationRecord>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<SharedMediaAllocationRecord>()) == 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: h.photo.appendingPathComponent("PhotoPreparation").path).isEmpty)
    }

    @Test(arguments: [SharedMediaPhotoBoundary.beforeCompletionSave, .beforeReadback])
    func uncertainWorkRemainsChargedAcrossRestart(_ boundary: SharedMediaPhotoBoundary) async throws {
        let h = try Harness(), calls = Calls(), bytes = PhotoPreparationTestHarness.image()
        var owner: SharedMediaPhotoAcquisitionOwner? = try h.owner()
        owner!.setFault { if $0 == boundary { throw Fault.injected } }
        await #expect(throws: (any Error).self) {
            try await owner!.acquire(packageID: UUID(), draftGeneration: UUID(), ordinal: 0, load: { await calls.hit(); return bytes })
        }
        #expect(await calls.count == (boundary == .beforeReadback ? 0 : 1))
        let context = ModelContext(h.container)
        let allocation = try #require(context.fetch(FetchDescriptor<SharedMediaAllocationRecord>()).first)
        #expect(allocation.stateRaw == "p1Held" && allocation.reservedBytes == PhotoPreparationPolicy.original)
        #expect(try context.fetchCount(FetchDescriptor<PhotoPreparationLease>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<PhotoPreparationAsset>()) == 0)
        if boundary == .beforeCompletionSave {
            #expect(try Data(contentsOf: h.photo.appendingPathComponent("PhotoPreparation").appendingPathComponent(allocation.fileToken)) == bytes)
        }
        owner = nil
        let reopened = try h.owner(), recovery = try await reopened.recover()
        #expect(recovery.requiresRecovery && recovery.originals.isEmpty)
        await #expect(throws: PhotoPreparationFailure.cleanupPending) {
            try await reopened.acquire(packageID: UUID(), draftGeneration: UUID(), ordinal: 0, load: { await calls.hit(); return bytes })
        }
        #expect(await calls.count == (boundary == .beforeReadback ? 0 : 1))
    }

    @Test func committedButUnreadAcknowledgementRecoversExactHandle() async throws {
        let h = try Harness(), calls = Calls(), bytes = PhotoPreparationTestHarness.image()
        var owner: SharedMediaPhotoAcquisitionOwner? = try h.owner()
        var committed = false
        owner!.setFault {
            if $0 == .afterCompletionSave { committed = true; throw Fault.injected }
            if $0 == .beforeReadback && committed { throw Fault.injected }
        }
        await #expect(throws: (any Error).self) {
            try await owner!.acquire(packageID: UUID(), draftGeneration: UUID(), ordinal: 0, load: { await calls.hit(); return bytes })
        }
        owner = nil
        let reopened = try h.owner(), recovery = try await reopened.recover()
        let handle = try #require(recovery.originals.first)
        #expect(!recovery.requiresRecovery && recovery.originals.count == 1)
        #expect(try await reopened.originalData(handle) == bytes)
        #expect(await calls.count == 1)
    }

    @Test func standaloneOwnersCannotBypassStoreOrRootBinding() async throws {
        let h = try Harness()
        var standalone: PhotoOriginalPreparationOwner? = try h.standalone(root: h.other)
        #expect(throws: SharedMediaStorageFailure.busy) { try h.owner() }
        #expect(standalone != nil)
        standalone = nil
        var adapter: SharedMediaPhotoAcquisitionOwner? = try h.owner()
        #expect(throws: PhotoPreparationFailure.busy) { try h.standalone(root: h.other) }
        #expect(throws: SharedMediaStorageFailure.busy) { try h.owner() }
        #expect(adapter != nil)
        adapter = nil
        #expect(throws: PhotoPreparationFailure.unsupportedComposition) { try h.standalone(root: h.other) }
        // A different database cannot bypass the persistent media-root marker.
        let other = try Harness()
        let foreign = try other.standalone(root: h.photo)
        await #expect(throws: PhotoPreparationFailure.unsupportedComposition) { try await foreign.recover() }
    }

    @Test func firstBindingRejectsExistingNamespaceAndP1Rows() async throws {
        let h = try Harness(), namespace = h.photo.appendingPathComponent("PhotoPreparation")
        try FileManager.default.createDirectory(at: namespace, withIntermediateDirectories: false)
        try Data([1]).write(to: namespace.appendingPathComponent("unknown"))
        #expect(throws: PhotoPreparationFailure.inconsistentOwnership) { try h.owner() }
        let other = try Harness(), bytes = PhotoPreparationTestHarness.image()
        var standalone: PhotoOriginalPreparationOwner? = try other.standalone(root: other.photo)
        _ = try await standalone!.acquire(packageID: UUID(), draftGeneration: UUID(), ordinal: 0, sourceKind: "fixture", load: { bytes })
        standalone = nil
        #expect(throws: SharedMediaStorageFailure.conflict) { try other.owner() }
    }

    @Test(arguments: [false, true])
    func missingOrReplacedOriginalNeverRegeneratesBytes(replace: Bool) async throws {
        let h = try Harness(), bytes = PhotoPreparationTestHarness.image()
        var owner: SharedMediaPhotoAcquisitionOwner? = try h.owner()
        _ = try await owner!.acquire(packageID: UUID(), draftGeneration: UUID(), ordinal: 0, load: { bytes })
        owner = nil
        let context = ModelContext(h.container)
        let asset = try #require(context.fetch(FetchDescriptor<PhotoPreparationAsset>()).first)
        let url = h.photo.appendingPathComponent("PhotoPreparation").appendingPathComponent(asset.fileToken)
        try FileManager.default.removeItem(at: url)
        if replace { try bytes.write(to: url) }
        let reopened = try h.owner()
        await #expect(throws: (any Error).self) { try await reopened.recover() }
        #expect(try context.fetchCount(FetchDescriptor<SharedMediaReferenceRecord>()) == 1)
        #expect(try context.fetch(FetchDescriptor<SharedMediaAllocationRecord>()).first?.materializedBytes == Int64(bytes.count))
    }

    @Test func maximumOriginalAndCapPlusOnePreserveExactBytes() async throws {
        let h = try Harness(), owner = try h.owner()
        var data = PhotoPreparationTestHarness.image()
        data.append(Data(repeating: 0, count: Int(PhotoPreparationPolicy.original) - data.count))
        let bytes = data, calls = Calls()
        let handle = try await owner.acquire(packageID: UUID(), draftGeneration: UUID(), ordinal: 0, load: { bytes })
        #expect(try await owner.originalData(handle) == bytes)
        await #expect(throws: (any Error).self) {
            try await owner.acquire(packageID: UUID(), draftGeneration: UUID(), ordinal: 0,
                maximumBytes: PhotoPreparationPolicy.original + 1, load: { await calls.hit(); return bytes })
        }
        #expect(await calls.count == 0)
    }

    @Test func dualLogicalBudgetAndMetadataDoNotDoubleReservePhysicalSpace() throws {
        let package = UUID(), mib = PhotoPreparationPolicy.mib
        var totals = SharedMediaStoragePolicy.Totals()
        try totals.include(.init(packageID: package, pool: .durable, materialized: 0, reserved: 32 * mib))
        try totals.includeLogical(package: package, pool: .acquisition, bytes: 32 * mib)
        try totals.includeLogical(package: package, pool: .durable, bytes: 1 * mib)
        try totals.checkAvailable(288 * mib)
        #expect(throws: SharedMediaStorageFailure.capacity) { try totals.checkAvailable(288 * mib - 1) }
        var packageLimit = SharedMediaStoragePolicy.Totals()
        try packageLimit.include(.init(packageID: package, pool: .durable, materialized: 95 * mib, reserved: 0))
        try packageLimit.includeLogical(package: package, pool: .durable, bytes: mib)
        #expect(throws: SharedMediaStorageFailure.capacity) { try packageLimit.includeLogical(package: package, pool: .durable, bytes: 1) }
        var acquisition = SharedMediaStoragePolicy.Totals()
        try acquisition.includeLogical(package: package, pool: .acquisition, bytes: 96 * mib)
        #expect(throws: SharedMediaStorageFailure.capacity) { try acquisition.includeLogical(package: package, pool: .acquisition, bytes: 1) }
    }

    @Test(arguments: ["edge", "account", "token", "lease", "metadata"])
    func corruptedPairAndMetadataBlockReopen(field: String) async throws {
        let h = try Harness(), bytes = PhotoPreparationTestHarness.image()
        var owner: SharedMediaPhotoAcquisitionOwner? = try h.owner()
        _ = try await owner!.acquire(packageID: UUID(), draftGeneration: UUID(), ordinal: 0, load: { bytes })
        owner = nil
        let context = ModelContext(h.container)
        let edge = try #require(context.fetch(FetchDescriptor<SharedMediaReferenceRecord>()).first)
        switch field {
        case "edge": edge.ownerID = UUID().uuidString.lowercased()
        case "account": edge.accountID = UUID()
        case "token": try #require(context.fetch(FetchDescriptor<SharedMediaAllocationRecord>()).first).fileToken = UUID().uuidString
        case "lease": try #require(context.fetch(FetchDescriptor<SharedMediaLeaseRecord>()).first).purposeRaw = "localQualification"
        default: try #require(context.fetch(FetchDescriptor<PhotoPreparationRecord>()).first).supportingContextData = Data("{}".utf8)
        }
        try context.save()
        #expect(throws: (any Error).self) { try h.owner() }
    }

    @Test func accountDrainWaitsForActualCallbackAndRetainsCharge() async throws {
        let h = try Harness(), owner = try h.owner(), gate = CallbackGate(), bytes = PhotoPreparationTestHarness.image()
        let work = Task { try await owner.acquire(packageID: UUID(), draftGeneration: UUID(), ordinal: 0, load: { await gate.wait(); return bytes }) }
        await gate.waitUntilStarted()
        var finished = false
        let drain = Task { let result = await owner.invalidateAndAwaitForAccountTransition(); finished = true; return result }
        for _ in 0..<10 { await Task.yield() }
        #expect(!finished)
        await gate.release()
        _ = await work.result
        #expect(await drain.value == false)
        let context = ModelContext(h.container)
        #expect(try context.fetchCount(FetchDescriptor<PhotoPreparationAsset>()) == 0)
        #expect(try context.fetch(FetchDescriptor<SharedMediaAllocationRecord>()).first?.reservedBytes == PhotoPreparationPolicy.original)
    }

    @Test func interruptedChunkRetainsOnlyItsFixedPartialAndMaximumCharge() async throws {
        let h = try Harness(), calls = Calls()
        var data = PhotoPreparationTestHarness.image()
        data.append(Data(repeating: 0, count: 131_072 - data.count))
        let bytes = data
        var owner: SharedMediaPhotoAcquisitionOwner? = try h.owner()
        await owner!.setWriteFault { _ in throw Fault.injected }
        await #expect(throws: Fault.injected) {
            try await owner!.acquire(packageID: UUID(), draftGeneration: UUID(), ordinal: 0, load: { await calls.hit(); return bytes })
        }
        let context = ModelContext(h.container)
        let work = try #require(context.fetch(FetchDescriptor<PhotoPreparationLease>()).first)
        let partial = h.photo.appendingPathComponent("PhotoPreparation").appendingPathComponent(work.partialFileToken)
        #expect(try Data(contentsOf: partial).count == 65_536)
        #expect(work.reservedByteCount == PhotoPreparationPolicy.original)
        #expect(!FileManager.default.fileExists(atPath: h.photo.appendingPathComponent("PhotoPreparation").appendingPathComponent(work.finalFileToken).path))
        owner = nil
        let reopened = try h.owner()
        #expect(try await reopened.recover().requiresRecovery)
        #expect(await calls.count == 1)
    }

    @Test func fifthPackageDoesNotInvokeProvider() async throws {
        let h = try Harness(), owner = try h.owner(), bytes = PhotoPreparationTestHarness.image(), calls = Calls()
        for _ in 0..<4 {
            _ = try await owner.acquire(packageID: UUID(), draftGeneration: UUID(), ordinal: 0, load: { bytes })
        }
        await #expect(throws: (any Error).self) {
            try await owner.acquire(packageID: UUID(), draftGeneration: UUID(), ordinal: 0, load: { await calls.hit(); return bytes })
        }
        #expect(await calls.count == 0)
        #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<PhotoPreparationRecord>()) == 4)
    }

    @Test func replacedPhotoDirectoryAndPartialBindingFailClosed() async throws {
        let h = try Harness()
        var owner: SharedMediaPhotoAcquisitionOwner? = try h.owner()
        try FileManager.default.moveItem(at: h.photo, to: h.base.appendingPathComponent("retained-photo"))
        try FileManager.default.createDirectory(at: h.photo, withIntermediateDirectories: false)
        await #expect(throws: (any Error).self) { try await owner!.recover() }
        owner = nil
        #expect(throws: (any Error).self) { try h.owner() }
        let other = try Harness()
        var bound: SharedMediaPhotoAcquisitionOwner? = try other.owner()
        #expect(bound != nil)
        bound = nil
        let context = ModelContext(other.container)
        try context.delete(model: SharedMediaInventoryRecord.self)
        try context.save()
        #expect(throws: (any Error).self) { try other.owner() }
    }

    @Test func genericMutationsCannotReachAdapterMode() throws {
        let h = try Harness()
        let storage = try SharedMediaStorageRepository(container: h.container, authorityRoot: h.root,
            inventoryID: h.inventory, mode: .p1Qualification, sources: [SharedMediaPhotoLedger.namespace: h.photo])
        let snapshot = try storage.snapshot()
        #expect(throws: SharedMediaStorageFailure.closed) { try storage.closeAdmission(expected: snapshot) }
        #expect(throws: SharedMediaStorageFailure.closed) { try storage.retireAccountReferences(h.accountID, expected: snapshot) }
        #expect(throws: SharedMediaStorageFailure.closed) { try storage.releaseReference(id: UUID(), expected: snapshot) }
        #expect(throws: SharedMediaStorageFailure.closed) { try storage.reserve(.init(id: UUID(), packageID: UUID(), accountID: h.accountID, pool: .durable, bytes: 1), expected: snapshot) }
        #expect(try storage.snapshot() == snapshot)
    }

    @Test(arguments: [PhotoPreparationInspectionStage.initialEmpty, .inventory])
    func directoryReadErrorsCannotBecomeEmptyOrCompleteInventory(stage: PhotoPreparationInspectionStage) async throws {
        let h = try Harness(), calls = Calls()
        try FileManager.default.createDirectory(at: h.photo.appendingPathComponent("PhotoPreparation"), withIntermediateDirectories: false)
        if stage == .initialEmpty {
            #expect(throws: PhotoPreparationFailure.unavailable) { try h.owner(inspection: .init(failing: stage)) }
            #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<SharedMediaInventoryRecord>()) == 0)
            let owner = try h.owner()
            #expect(try await owner.recover().originals.isEmpty)
        } else {
            let owner = try h.owner(inspection: .init(failing: stage))
            await #expect(throws: PhotoPreparationFailure.unavailable) {
                try await owner.acquire(packageID: UUID(), draftGeneration: UUID(), ordinal: 0, load: { await calls.hit(); return Data() })
            }
            #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<SharedMediaAllocationRecord>()) == 0)
        }
        #expect(await calls.count == 0)
    }

    @Test(arguments: [SharedMediaStorageMode.observation, .qualification])
    func everySharedModeParticipatesInStandaloneExclusion(mode: SharedMediaStorageMode) throws {
        let h = try Harness()
        var standalone: PhotoOriginalPreparationOwner? = try h.standalone(root: h.other)
        #expect(standalone != nil)
        #expect(throws: SharedMediaStorageFailure.busy) {
            try SharedMediaStorageRepository(container: h.container, authorityRoot: h.root,
                inventoryID: h.inventory, mode: mode)
        }
        standalone = nil
        let shared = try SharedMediaStorageRepository(container: h.container, authorityRoot: h.root,
            inventoryID: h.inventory, mode: mode)
        #expect(throws: PhotoPreparationFailure.busy) { try h.standalone(root: h.other) }
        #expect(try shared.snapshot().revision == 0)
    }

    @Test func colocatedPurgeRetainsStoreFenceUntilOwnerTeardown() async throws {
        let h = try PhotoPreparationTestHarness(), bytes = PhotoPreparationTestHarness.image()
        let authority = h.root.deletingLastPathComponent().appendingPathComponent("purge-authority-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: authority, withIntermediateDirectories: false)
        var owner: PhotoOriginalPreparationOwner? = try h.owner()
        _ = try await owner!.acquire(packageID: UUID(), draftGeneration: UUID(), ordinal: 0, sourceKind: "fixture", load: { bytes })
        let other = try PhotoPreparationLockedFiles(root: h.root)
        await #expect(throws: PhotoPreparationFailure.busy) { try await owner!.purge() }
        #expect(try PhotoPreparationRepository.hasLiabilities(in: ModelContext(h.container)))
        other.close()
        try await owner!.purge()
        #expect(!FileManager.default.fileExists(atPath: h.root.appendingPathComponent("PhotoPreparation").path))
        #expect(FileManager.default.fileExists(atPath: h.root.appendingPathComponent(SharedMediaStoreReadFence.name).path))
        #expect(throws: SharedMediaStorageFailure.busy) {
            try SharedMediaStorageRepository(container: h.container, authorityRoot: authority,
                inventoryID: UUID(), mode: .observation)
        }
        owner = nil
        let shared = try SharedMediaStorageRepository(container: h.container, authorityRoot: authority,
            inventoryID: UUID(), mode: .observation)
        #expect(try shared.snapshot().revision == 0)
    }

    @Test(arguments: ["replacement", "hardlink", "nonempty", "symlink"])
    func fenceCorruptionInvalidatesStandaloneWithoutProviderReplay(kind: String) async throws {
        let h = try Harness(), owner = try h.standalone(root: h.other), calls = Calls()
        let parent = h.container.configurations.first!.url.deletingLastPathComponent()
        let fence = parent.appendingPathComponent(SharedMediaStoreReadFence.name)
        let retained = parent.appendingPathComponent("retained-fence")
        switch kind {
        case "hardlink": try FileManager.default.linkItem(at: fence, to: retained)
        case "nonempty": try Data([1]).write(to: fence)
        default:
            try FileManager.default.moveItem(at: fence, to: retained)
            if kind == "symlink" { try FileManager.default.createSymbolicLink(at: fence, withDestinationURL: retained) }
            else { try Data().write(to: fence) }
        }
        await #expect(throws: (any Error).self) {
            try await owner.acquire(packageID: UUID(), draftGeneration: UUID(), ordinal: 0, sourceKind: "fixture", load: { await calls.hit(); return Data() })
        }
        #expect(await calls.count == 0)
        #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<PhotoPreparationRecord>()) == 0)
        if kind == "hardlink" { try FileManager.default.removeItem(at: retained) }
        // Restoring the link count cannot rehabilitate a previously invalidated owner.
        await #expect(throws: (any Error).self) { try await owner.recover() }
    }

    @Test func sharedOwnerAlsoRejectsFenceReplacement() throws {
        let h = try Harness()
        let shared = try SharedMediaStorageRepository(container: h.container, authorityRoot: h.root,
            inventoryID: h.inventory, mode: .qualification)
        let fence = h.container.configurations.first!.url.deletingLastPathComponent().appendingPathComponent(SharedMediaStoreReadFence.name)
        try FileManager.default.moveItem(at: fence, to: fence.appendingPathExtension("retained"))
        try Data().write(to: fence)
        #expect(throws: SharedMediaStorageFailure.conflict) { try shared.snapshot() }
    }

    @Test(arguments: [SharedMediaFenceSyncStage.file, .parent])
    func existingUnsynchronizedFenceCannotBypassSynchronization(stage: SharedMediaFenceSyncStage) async throws {
        let h = try Harness(), store = h.container.configurations.first!.url
        let fence = store.deletingLastPathComponent().appendingPathComponent(SharedMediaStoreReadFence.name)
        let fd = Darwin.open(fence.path, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        #expect(fd >= 0)
        if fd >= 0 { Darwin.close(fd) } // Deliberately no file/parent fsync.
        #expect(throws: PhotoPreparationFailure.unavailable) {
            try SharedMediaStoreReadFence(store: store, synchronization: .init(failing: stage))
        }
        #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<SharedMediaInventoryRecord>()) == 0)
        #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<PhotoPreparationRecord>()) == 0)
        // A normal opener must establish durability itself and can then bind.
        let owner = try h.owner()
        #expect(try await owner.recover().originals.isEmpty)
    }

    @Test(arguments: [true, false])
    func sharedOriginalSurvivesEitherRetirementOrder(originFirst: Bool) async throws {
        let h = try Harness(), bytes = PhotoPreparationTestHarness.image()
        var owner: SharedMediaPhotoAcquisitionOwner? = try h.owner()
        let original = try await owner!.acquire(packageID: UUID(), draftGeneration: UUID(), ordinal: 0, load: { bytes })
        let request = try owner!.prepareShare(original, packageID: UUID(), draftGeneration: UUID())
        let shared = try await owner!.share(request)
        let first = originFirst ? original : shared, survivor = originFirst ? shared : original
        #expect(try await owner!.retire(first) == .referenceRetired)
        let context = ModelContext(h.container)
        #expect(try context.fetchCount(FetchDescriptor<PhotoPreparationRecord>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<SharedMediaAllocationRecord>()) == 1)
        #expect(try context.fetch(FetchDescriptor<SharedMediaAllocationRecord>()).first?.packageID == original.packageID)
        owner = nil
        let reopened = try h.owner()
        #expect(try await reopened.originalData(survivor) == bytes)
        #expect(try await reopened.recover().originals == [survivor])
        await #expect(throws: (any Error).self) { try await reopened.originalData(first) }
        #expect(try await reopened.retire(first) == .referenceAbsent)
        #expect(try await reopened.retire(survivor) == .physicalReleaseConfirmed)
        #expect(try await reopened.recover().originals.isEmpty)
        let fresh = ModelContext(h.container)
        #expect(try fresh.fetchCount(FetchDescriptor<PhotoPreparationRecord>()) == 0)
        #expect(try fresh.fetchCount(FetchDescriptor<PhotoPreparationAsset>()) == 0)
        #expect(try fresh.fetchCount(FetchDescriptor<SharedMediaAllocationRecord>()) == 0)
        #expect(try fresh.fetchCount(FetchDescriptor<SharedMediaLeaseRecord>()) == 0)
        #expect(try fresh.fetchCount(FetchDescriptor<SharedMediaReferenceRecord>()) == 0)
    }

    @Test func shareRequestRecoversAcrossRestartAndCannotResurrectReclaimedEdge() async throws {
        let h = try Harness(), bytes = PhotoPreparationTestHarness.image()
        var owner: SharedMediaPhotoAcquisitionOwner? = try h.owner()
        let original = try await owner!.acquire(packageID: UUID(), draftGeneration: UUID(), ordinal: 0, load: { bytes })
        let request = try owner!.prepareShare(original, packageID: UUID(), draftGeneration: UUID())
        let encoded = try JSONEncoder().encode(request)
        var saved = false
        owner!.setFault {
            if $0 == .afterShareSave { saved = true; throw Fault.injected }
            if $0 == .beforeLifecycleReadback && saved { throw Fault.injected }
        }
        await #expect(throws: Fault.injected) { try await owner!.share(request) }
        owner = nil
        let reopened = try h.owner()
        let retained = try JSONDecoder().decode(SharedMediaPhotoShareRequest.self, from: encoded)
        let shared = try await reopened.share(retained)
        #expect(try await reopened.share(retained) == shared)
        #expect(try await reopened.retire(shared) == .referenceRetired)
        await #expect(throws: SharedMediaStorageFailure.stale) { try await reopened.share(retained) }
        let freshRequest = try reopened.prepareShare(original, packageID: shared.packageID, draftGeneration: shared.draftGeneration)
        let replacement = try await reopened.share(freshRequest)
        #expect(replacement.referenceID != shared.referenceID)
        #expect(try await reopened.retire(shared) == .referenceAbsent)
        #expect(try await reopened.originalData(replacement) == bytes)
    }

    @Test(arguments: [SharedMediaPhotoBoundary.beforeRetirementSave, .afterRetirementSave, .beforeReleaseSave, .afterReleaseSave])
    func retirementSaveFaultsReconcileWithoutCapacityLoss(boundary: SharedMediaPhotoBoundary) async throws {
        let h = try Harness(), bytes = PhotoPreparationTestHarness.image()
        var owner: SharedMediaPhotoAcquisitionOwner? = try h.owner()
        let original = try await owner!.acquire(packageID: UUID(), draftGeneration: UUID(), ordinal: 0, load: { bytes })
        owner!.setFault { if $0 == boundary { throw Fault.injected } }
        if boundary == .beforeRetirementSave || boundary == .beforeReleaseSave {
            await #expect(throws: Fault.injected) { try await owner!.retire(original) }
        } else {
            #expect(try await owner!.retire(original) == .physicalReleaseConfirmed)
        }
        let c = ModelContext(h.container)
        #expect(try c.fetchCount(FetchDescriptor<SharedMediaAllocationRecord>()) == (boundary == .beforeRetirementSave || boundary == .beforeReleaseSave ? 1 : 0))
        if boundary == .beforeReleaseSave {
            let allocation = try #require(c.fetch(FetchDescriptor<SharedMediaAllocationRecord>()).first)
            #expect(allocation.stateRaw == "p1Retiring" && allocation.materializedBytes == Int64(bytes.count))
            #expect(!FileManager.default.fileExists(atPath: h.photo.appendingPathComponent("PhotoPreparation").appendingPathComponent(allocation.fileToken).path))
        }
        owner = nil
        let reopened = try h.owner()
        if boundary == .beforeRetirementSave { _ = try await reopened.retire(original) }
        else { try await reopened.finishRetirements() }
        #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<SharedMediaAllocationRecord>()) == 0)
    }

    @Test(arguments: [SharedMediaPhotoReleaseBoundary.beforeUnlink, .afterUnlink, .beforeSync, .afterSync])
    func interruptedPhysicalReleaseRemainsChargedAndReopens(boundary: SharedMediaPhotoReleaseBoundary) async throws {
        let h = try Harness(), bytes = PhotoPreparationTestHarness.image()
        var owner: SharedMediaPhotoAcquisitionOwner? = try h.owner()
        let original = try await owner!.acquire(packageID: UUID(), draftGeneration: UUID(), ordinal: 0, load: { bytes })
        await owner!.setReleaseFault { if $0 == boundary { throw Fault.injected } }
        await #expect(throws: Fault.injected) { try await owner!.retire(original) }
        let c = ModelContext(h.container)
        #expect(try c.fetch(FetchDescriptor<SharedMediaAllocationRecord>()).first?.materializedBytes == Int64(bytes.count))
        #expect(try c.fetch(FetchDescriptor<PhotoPreparationReference>()).allSatisfy { !$0.isLive })
        owner = nil
        let reopened = try h.owner()
        #expect(try await reopened.recover().requiresRecovery)
        try await reopened.finishRetirements()
        #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<SharedMediaAllocationRecord>()) == 0)
    }

    @Test(arguments: ["replacement", "symlink", "hardlink", "missing", "parent"])
    func retirementNeverDeletesChangedOriginalOrReleasesReplacedDirectory(kind: String) async throws {
        let h = try Harness(), bytes = PhotoPreparationTestHarness.image()
        var owner: SharedMediaPhotoAcquisitionOwner? = try h.owner()
        let handle = try await owner!.acquire(packageID: UUID(), draftGeneration: UUID(), ordinal: 0, load: { bytes })
        let asset = try #require(ModelContext(h.container).fetch(FetchDescriptor<PhotoPreparationAsset>()).first)
        let url = h.photo.appendingPathComponent("PhotoPreparation").appendingPathComponent(asset.fileToken)
        if kind == "parent" {
            await owner!.setReleaseFault { if $0 == .afterUnlink { throw Fault.injected } }
            await #expect(throws: Fault.injected) { try await owner!.retire(handle) }
            owner = nil
            let parent = url.deletingLastPathComponent()
            try FileManager.default.moveItem(at: parent, to: h.other.appendingPathComponent("retained-parent"))
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
            let reopened = try h.owner()
            await #expect(throws: (any Error).self) { try await reopened.finishRetirements() }
        } else {
            if kind == "hardlink" { try FileManager.default.linkItem(at: url, to: h.other.appendingPathComponent("other")) }
            else {
                try FileManager.default.moveItem(at: url, to: h.other.appendingPathComponent("retained-original"))
                if kind == "replacement" { try bytes.write(to: url) }
                if kind == "symlink" { try FileManager.default.createSymbolicLink(at: url, withDestinationURL: h.other.appendingPathComponent("retained-original")) }
            }
            await #expect(throws: (any Error).self) { try await owner!.retire(handle) }
        }
        #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<SharedMediaAllocationRecord>()) == 1)
    }

    @Test func sharedAccountingCountsPhysicalBytesOnceAndLogicalLimitsIndependently() throws {
        let mib = PhotoPreparationPolicy.mib
        var totals = SharedMediaStoragePolicy.Totals()
        try totals.includePhotoPhysical(materialized: 64 * mib, reserved: 32 * mib)
        for _ in 0..<4 { try totals.includePhotoPackage(id: UUID(), bytes: 96 * mib) }
        try totals.checkAvailable(288 * mib)
        #expect(throws: SharedMediaStorageFailure.capacity) { try totals.checkAvailable(288 * mib - 1) }
        #expect(throws: SharedMediaStorageFailure.capacity) { try totals.includePhotoPackage(id: UUID(), bytes: 1) }
        var limit = SharedMediaStoragePolicy.Totals()
        #expect(throws: SharedMediaStorageFailure.capacity) { try limit.includePhotoPackage(id: UUID(), bytes: 96 * mib + 1) }
        var durable = SharedMediaStoragePolicy.Totals()
        #expect(throws: SharedMediaStorageFailure.capacity) { try durable.includePhotoPhysical(materialized: 384 * mib + 1, reserved: 0) }
    }

    @Test func repeatedShareRetireReclaimsRowsAndPackageSlots() async throws {
        let h = try Harness(), owner = try h.owner(), bytes = PhotoPreparationTestHarness.image()
        let original = try await owner.acquire(packageID: UUID(), draftGeneration: UUID(), ordinal: 0, load: { bytes })
        for _ in 0..<100 {
            let request = try owner.prepareShare(original, packageID: UUID(), draftGeneration: UUID())
            let shared = try await owner.share(request)
            #expect(try await owner.retire(shared) == .referenceRetired)
        }
        let context = ModelContext(h.container)
        #expect(try context.fetchCount(FetchDescriptor<PhotoPreparationRecord>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<SharedMediaReferenceRecord>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<SharedMediaAllocationRecord>()) == 1)
        #expect(try await owner.originalData(original) == bytes)
        _ = try await owner.retire(original)
    }

    @Test func closedReleaseProofCannotBeReplayedOrUsedByAnotherLifetime() async throws {
        let h = try Harness(), bytes = PhotoPreparationTestHarness.image()
        var owner: SharedMediaPhotoAcquisitionOwner? = try h.owner()
        let original = try await owner!.acquire(packageID: UUID(), draftGeneration: UUID(), ordinal: 0, load: { bytes })
        owner = nil
        var repository: SharedMediaStorageRepository? = try h.repository()
        let file = try repository!.resolvePhoto(original)
        let inspection = try repository!.photoFiles!.inspectSharedRetirement(file)
        // The native codec accepts the actual descriptor producer's shape;
        // this synthetic binding grants no native cleanup authority.
        let native = try SharedMediaNativeRetirementIdentity(retirementID: UUID(), assetID: original.assetID,
            assetGeneration: original.assetGeneration, inventoryID: UUID(), inventoryGeneration: UUID(),
            ownerID: original.ownerID, proof: inspection.identity)
        #expect(try SharedMediaNativeRetirementIdentity.decode(native.encoded()) == native)
        try repository!.retirePhoto(original, inspection: inspection)
        guard case .retiring(let intent) = try repository!.photoReferenceState(original) else { Issue.record("No retirement"); return }
        let proof = try repository!.photoFiles!.releaseSharedPhoto(intent)
        try repository!.releasePhoto(proof)
        #expect(throws: (any Error).self) { try repository!.releasePhoto(proof) }
        repository = nil
        let reopened = try h.repository()
        #expect(throws: SharedMediaStorageFailure.closed) { try reopened.releasePhoto(proof) }
        #expect(throws: PhotoPreparationFailure.unsupportedComposition) { try reopened.photoFiles!.releaseSharedPhoto(intent) }
    }

    @Test func heldAcquisitionBlocksReferenceAndReleaseMutations() async throws {
        let h = try Harness(), bytes = PhotoPreparationTestHarness.image()
        var owner: SharedMediaPhotoAcquisitionOwner? = try h.owner()
        let original = try await owner!.acquire(packageID: UUID(), draftGeneration: UUID(), ordinal: 0, load: { bytes })
        let request = try owner!.prepareShare(original, packageID: UUID(), draftGeneration: UUID())
        owner!.setFault { if $0 == .beforeCompletionSave { throw Fault.injected } }
        await #expect(throws: (any Error).self) {
            try await owner!.acquire(packageID: UUID(), draftGeneration: UUID(), ordinal: 0, load: { bytes })
        }
        owner = nil
        let reopened = try h.owner()
        await #expect(throws: PhotoPreparationFailure.cleanupPending) { try await reopened.share(request) }
        await #expect(throws: PhotoPreparationFailure.cleanupPending) { try await reopened.retire(original) }
        await #expect(throws: PhotoPreparationFailure.cleanupPending) { try await reopened.finishRetirements() }
        #expect(try await reopened.originalData(original) == bytes)
    }

    @Test func sharingHonorsPackageCeilingAndRejectsForeignAndStaleClaims() async throws {
        let h = try Harness(), owner = try h.owner(), bytes = PhotoPreparationTestHarness.image()
        let original = try await owner.acquire(packageID: UUID(), draftGeneration: UUID(), ordinal: 0, load: { bytes })
        for _ in 0..<3 {
            _ = try await owner.share(owner.prepareShare(original, packageID: UUID(), draftGeneration: UUID()))
        }
        let fifth = try owner.prepareShare(original, packageID: UUID(), draftGeneration: UUID())
        await #expect(throws: (any Error).self) { try await owner.share(fifth) }
        let foreign = PhotoOriginalReference(ownerID: UUID(), packageID: original.packageID, referenceID: original.referenceID,
            assetID: original.assetID, assetGeneration: original.assetGeneration, draftGeneration: original.draftGeneration, referenceRevision: 0)
        await #expect(throws: PhotoPreparationFailure.accountChanged) { try await owner.retire(foreign) }
        let stale = PhotoOriginalReference(ownerID: original.ownerID, packageID: original.packageID, referenceID: original.referenceID,
            assetID: original.assetID, assetGeneration: UUID(), draftGeneration: original.draftGeneration, referenceRevision: 0)
        await #expect(throws: (any Error).self) { try await owner.retire(stale) }
        #expect(try await owner.originalData(original) == bytes)
    }

    @Test func retirementRecoveryIsAccountScoped() async throws {
        let h = try Harness(), bytes = PhotoPreparationTestHarness.image()
        var owner: SharedMediaPhotoAcquisitionOwner? = try h.owner()
        let original = try await owner!.acquire(packageID: UUID(), draftGeneration: UUID(), ordinal: 0, load: { bytes })
        await owner!.setReleaseFault { if $0 == .beforeUnlink { throw Fault.injected } }
        await #expect(throws: Fault.injected) { try await owner!.retire(original) }
        owner = nil
        var foreign: SharedMediaPhotoAcquisitionOwner? = try .init(container: h.container, authorityRoot: h.root, photoRoot: h.photo,
            inventoryID: h.inventory, account: PhotoOriginalPreparationOwner.syntheticAccount(ownerID: UUID(), runtime: h.runtime))
        try await foreign!.finishRetirements()
        #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<SharedMediaAllocationRecord>()) == 1)
        foreign = nil
        let reopened = try h.owner()
        #expect(await reopened.invalidateAndAwaitForAccountTransition() == false)
        await #expect(throws: (any Error).self) { try await reopened.finishRetirements() }
        #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<SharedMediaAllocationRecord>()) == 1)
    }

    @Test func accountDrainWaitsForRetirementIOAndPreservesPendingIntent() async throws {
        let h = try Harness(), owner = try h.owner(), bytes = PhotoPreparationTestHarness.image(), gate = CallbackGate()
        let original = try await owner.acquire(packageID: UUID(), draftGeneration: UUID(), ordinal: 0, load: { bytes })
        await owner.setReleasePause { await gate.wait() }
        let work = Task { try await owner.retire(original) }
        await gate.waitUntilStarted()
        await #expect(throws: PhotoPreparationFailure.busy) { try await owner.originalData(original) }
        var finished = false
        let drain = Task { let value = await owner.invalidateAndAwaitForAccountTransition(); finished = true; return value }
        for _ in 0..<10 { await Task.yield() }
        #expect(!finished)
        #expect(throws: SharedMediaStorageFailure.busy) { try h.owner() }
        await gate.release()
        _ = await work.result
        #expect(await drain.value == false)
        let c = ModelContext(h.container)
        #expect(try c.fetch(FetchDescriptor<SharedMediaAllocationRecord>()).first?.stateRaw == "p1Retiring")
        #expect(try c.fetch(FetchDescriptor<SharedMediaAllocationRecord>()).first?.materializedBytes == Int64(bytes.count))
    }

    @Test func emptyDirectoryRecoveryPrecedesCappedInventoryAndKeepsHeldPrefixes() async throws {
        let h = try Harness(), owner = try h.owner(), bytes = PhotoPreparationTestHarness.image()
        let handle = try await owner.acquire(packageID: UUID(), draftGeneration: UUID(), ordinal: 0, load: { bytes })
        let namespace = h.photo.appendingPathComponent("PhotoPreparation")
        let account = namespace.appendingPathComponent(h.accountID.uuidString.lowercased())
        for _ in 0..<270 {
            try FileManager.default.createDirectory(at: account.appendingPathComponent(UUID().uuidString.lowercased()), withIntermediateDirectories: false)
        }
        await #expect(throws: PhotoPreparationFailure.inconsistentOwnership) { try await owner.recover() }
        try await owner.finishRetirements()
        #expect(try await owner.originalData(handle) == bytes)
        #expect(try FileManager.default.contentsOfDirectory(atPath: account.path) == [handle.packageID.uuidString.lowercased()])
        _ = try await owner.retire(handle)
        #expect(try FileManager.default.contentsOfDirectory(atPath: namespace.path).isEmpty)
    }

    @Test func emptyDirectoryCleanupPreservesUnknownFilesAndSymlinks() async throws {
        let h = try Harness(), owner = try h.owner()
        let namespace = h.photo.appendingPathComponent("PhotoPreparation")
        let account = namespace.appendingPathComponent(UUID().uuidString.lowercased())
        let package = account.appendingPathComponent(UUID().uuidString.lowercased())
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        let unknown = package.appendingPathComponent("unknown")
        try Data([1]).write(to: unknown)
        await #expect(throws: (any Error).self) { try await owner.finishRetirements() }
        #expect(try Data(contentsOf: unknown) == Data([1]))
        try FileManager.default.removeItem(at: unknown)
        try FileManager.default.removeItem(at: package)
        try FileManager.default.createSymbolicLink(at: package, withDestinationURL: h.other)
        await #expect(throws: (any Error).self) { try await owner.finishRetirements() }
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: package.path) == h.other.path)
    }

    @MainActor private struct Harness {
        let base: URL
        let root: URL
        let photo: URL
        let other: URL
        let container: ModelContainer
        let inventory = UUID(), accountID = UUID(), runtime = AuthRuntimeState()
        init() throws {
            base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("shared-photo-" + UUID().uuidString)
            root = base.appendingPathComponent("authority")
            photo = base.appendingPathComponent("photo")
            other = base.appendingPathComponent("other")
            let db = base.appendingPathComponent("database")
            for directory in [root, photo, other, db] { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
            let schema = Schema(versionedSchema: CurrentSchema.self)
            container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: db.appendingPathComponent("ledger.store"), cloudKitDatabase: .none)])
        }
        func owner(inspection: PhotoPreparationDirectoryInspection = .init()) throws -> SharedMediaPhotoAcquisitionOwner {
            try .init(container: container, authorityRoot: root, photoRoot: photo, inventoryID: inventory,
                account: PhotoOriginalPreparationOwner.syntheticAccount(ownerID: accountID, runtime: runtime), inspection: inspection)
        }
        func repository() throws -> SharedMediaStorageRepository {
            try .init(container: container, authorityRoot: root, inventoryID: inventory, mode: .p1Qualification,
                sources: [SharedMediaPhotoLedger.namespace: photo])
        }
        func standalone(root: URL) throws -> PhotoOriginalPreparationOwner {
            try .qualification(container: container, root: root,
                account: PhotoOriginalPreparationOwner.syntheticAccount(ownerID: accountID, runtime: runtime))
        }
    }

    private actor Calls {
        var count = 0
        func hit() { count += 1 }
    }
    private actor CallbackGate {
        private var started = false
        private var resume: CheckedContinuation<Void, Never>?
        func wait() async { started = true; await withCheckedContinuation { resume = $0 } }
        func waitUntilStarted() async { while !started { await Task.yield() } }
        func release() { resume?.resume(); resume = nil }
    }
}
