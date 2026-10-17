import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Inactive shared media storage", .serialized)
@MainActor
struct SharedMediaStorageTests {
    @Test(arguments: [false, true])
    func derivativeOrphansBlockQualificationAndRetainLiabilities(saved: Bool) throws {
        let factories: [() -> any PersistentModel] = [
            { SharedMediaDerivativePairRecord(id: UUID(), nonce: UUID(), inventoryID: UUID(), inventoryGeneration: UUID(), expectedInventoryRevision: 0, ownerID: UUID(), packageID: UUID(), draftGeneration: UUID(), originalReferenceID: UUID(), originalReferenceRevision: 0, originalAssetID: UUID(), originalAssetGeneration: UUID(), ordinal: 0, expectedPackageRevision: 0, aiWorkID: UUID(), displayWorkID: UUID()) },
            { SharedMediaDerivativeWorkRecord(id: UUID(), pairID: UUID(), roleRaw: "aiInput", assetID: UUID(), assetGeneration: UUID(), referenceID: UUID(), leaseID: UUID(), writerEpoch: UUID(), byteCount: 1, sha256: String(repeating: "a", count: 64), contentType: "image/jpeg") }
        ]
        for makeRow in factories {
            let h = try Harness(), context = ModelContext(h.container)
            let row = makeRow()
            context.autosaveEnabled = false
            context.insert(row)
            #expect(try SharedMediaStorageRepository.hasLiabilities(in: context))
            if saved {
                try context.save()
                #expect(throws: SharedMediaStorageFailure.conflict) { try h.owner() }
                #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<SharedMediaInventoryRecord>()) == 0)
            }
        }
    }

    @Test func matchingDerivativeRowsWithoutOriginalCannotBypassInboxValidation() throws {
        let h = try Harness(nestedStore: true)
        let inbox = h.base.appendingPathComponent("inbox"), photo = h.base.appendingPathComponent("photo")
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: photo, withIntermediateDirectories: false)
        let owner = try SharedMediaStorageRepository(container: h.container, authorityRoot: h.root,
            inventoryID: h.inventory, mode: .p1InboxQualification,
            sources: [SharedMediaInboxFiles.namespace: inbox, SharedMediaPhotoLedger.namespace: photo])
        let before = try owner.snapshot()
        let pair = SharedMediaDerivativePairRecord(id: UUID(), nonce: UUID(), inventoryID: UUID(), inventoryGeneration: UUID(), expectedInventoryRevision: 0, ownerID: UUID(), packageID: UUID(), draftGeneration: UUID(), originalReferenceID: UUID(), originalReferenceRevision: 0, originalAssetID: UUID(), originalAssetGeneration: UUID(), ordinal: 0, expectedPackageRevision: 0, aiWorkID: UUID(), displayWorkID: UUID())
        let ai = SharedMediaDerivativeWorkRecord(id: UUID(), pairID: UUID(), roleRaw: "aiInput", assetID: UUID(), assetGeneration: UUID(), referenceID: UUID(), leaseID: UUID(), writerEpoch: UUID(), byteCount: 1, sha256: String(repeating: "a", count: 64), contentType: "image/jpeg")
        let display = SharedMediaDerivativeWorkRecord(id: UUID(), pairID: UUID(), roleRaw: "aiInput", assetID: UUID(), assetGeneration: UUID(), referenceID: UUID(), leaseID: UUID(), writerEpoch: UUID(), byteCount: 1, sha256: String(repeating: "a", count: 64), contentType: "image/jpeg")
        pair.inventoryID = h.inventory
        pair.aiWorkID = ai.id; pair.displayWorkID = display.id
        ai.pairID = pair.id; display.pairID = pair.id; display.roleRaw = "display"
        let context = ModelContext(h.container)
        context.insert(pair); context.insert(ai); context.insert(display)
        try context.save()
        #expect(throws: (any Error).self) { try owner.snapshot() }
        #expect(try SharedMediaStorageRepository.hasLiabilities(in: context))
        let inventory = try #require(context.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first)
        #expect(inventory.revision == before.revision)
        #expect(try context.fetchCount(FetchDescriptor<SharedMediaAllocationRecord>()) == 0)
    }

    @Test func reservationsSurviveReopenAndCannotRenewTheirAllowance() throws {
        let h = try Harness()
        var owner: SharedMediaStorageRepository? = try h.owner()
        let request = h.reservation(bytes: 96 * PhotoPreparationPolicy.mib)
        let saved = try owner!.reserve(request, expected: try owner!.snapshot())
        #expect(try owner!.reserve(request, expected: try owner!.snapshot()) == saved)
        #expect(throws: SharedMediaStorageFailure.conflict) {
            try owner!.reserve(.init(id: request.id, packageID: request.packageID, accountID: request.accountID,
                pool: .durable, bytes: request.bytes - 1), expected: saved)
        }
        owner = nil
        let reopened = try h.owner()
        #expect(try reopened.snapshot() == saved)
        #expect(throws: SharedMediaStorageFailure.capacity) {
            try reopened.reserve(.init(id: UUID(), packageID: request.packageID, accountID: request.accountID,
                pool: .durable, bytes: 1), expected: saved)
        }
        #expect(try reopened.snapshot() == saved)
    }

    @Test func exclusiveStoreAndRootBindingCannotBeBypassed() throws {
        let h = try Harness()
        var owner: SharedMediaStorageRepository? = try h.owner()
        #expect(throws: SharedMediaStorageFailure.busy) { try h.owner() }
        let alternate = h.base.appendingPathComponent("alternate")
        try FileManager.default.createDirectory(at: alternate, withIntermediateDirectories: false)
        #expect(throws: SharedMediaStorageFailure.busy) {
            try SharedMediaStorageRepository(container: h.container, authorityRoot: alternate,
                inventoryID: h.inventory, mode: .qualification)
        }
        #expect(try owner!.snapshot().revision == 0)
        owner = nil
        #expect(throws: SharedMediaStorageFailure.conflict) {
            try SharedMediaStorageRepository(container: h.container, authorityRoot: alternate,
                inventoryID: h.inventory, mode: .qualification)
        }
        try Data([1]).write(to: h.root.appendingPathComponent("unknown"))
        #expect(throws: SharedMediaStorageFailure.conflict) { try h.owner() }
    }

    @Test func distinctStoresInOneDirectoryCannotHaveConcurrentOwners() throws {
        let h = try Harness(), owner = try h.owner()
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let other = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema,
            url: h.base.appendingPathComponent("other.store"), cloudKitDatabase: .none)])
        let otherRoot = h.base.appendingPathComponent("other-authority")
        try FileManager.default.createDirectory(at: otherRoot, withIntermediateDirectories: false)
        #expect(throws: SharedMediaStorageFailure.busy) {
            try SharedMediaStorageRepository(container: other, authorityRoot: otherRoot,
                inventoryID: UUID(), mode: .qualification)
        }
        // Core Data remains usable while our independent directory lock is held.
        #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<SharedMediaInventoryRecord>()) == 1)
        #expect(try owner.snapshot().revision == 0)
    }

    @Test func replacedStoreDirectoryInvalidatesTheExistingOwner() throws {
        let h = try Harness(), owner = try h.owner()
        let retained = h.base.deletingLastPathComponent().appendingPathComponent("sma-retained-" + UUID().uuidString)
        // Preserve all SQLite files/sidecars; only the synthetic directory name changes.
        try FileManager.default.moveItem(at: h.base, to: retained)
        try FileManager.default.createDirectory(at: h.base, withIntermediateDirectories: false)
        #expect(throws: SharedMediaStorageFailure.conflict) { try owner.snapshot() }
    }

    @Test func missingLedgerCannotResetAnExistingAuthorityMarker() throws {
        let h = try Harness()
        var owner: SharedMediaStorageRepository? = try h.owner()
        _ = try owner!.reserve(h.reservation(bytes: 1), expected: try owner!.snapshot())
        owner = nil
        let context = ModelContext(h.container)
        try context.delete(model: SharedMediaAllocationRecord.self)
        try context.delete(model: SharedMediaInventoryRecord.self)
        try context.save()
        #expect(throws: SharedMediaStorageFailure.conflict) { try h.owner() }
    }

    @Test func replacedStoreAtSamePathCannotResetAuthority() throws {
        let base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("sma-replaced-" + UUID().uuidString)
        let root = base.appendingPathComponent("authority"), database = base.appendingPathComponent("database")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: database, withIntermediateDirectories: false)
        let inventory = UUID(), schema = Schema(versionedSchema: CurrentSchema.self), url = database.appendingPathComponent("fixture.store")
        try autoreleasepool {
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            let owner = try SharedMediaStorageRepository(container: container, authorityRoot: root, inventoryID: inventory, mode: .qualification)
            _ = try owner.reserve(.init(id: UUID(), packageID: UUID(), accountID: UUID(), pool: .durable, bytes: 1), expected: try owner.snapshot())
        }
        // Preserve the entire closed source SQLite directory and all sidecars.
        try FileManager.default.moveItem(at: database, to: base.appendingPathComponent("retained-database"))
        try FileManager.default.createDirectory(at: database, withIntermediateDirectories: false)
        let replacement = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
        #expect(throws: SharedMediaStorageFailure.conflict) {
            try SharedMediaStorageRepository(container: replacement, authorityRoot: root, inventoryID: inventory, mode: .qualification)
        }
    }

    @Test func sourceRootsCannotContainTheStoreOrAuthority() throws {
        let h = try Harness()
        #expect(throws: SharedMediaStorageFailure.invalid) {
            try SharedMediaStorageRepository(container: h.container, authorityRoot: h.root, inventoryID: h.inventory,
                mode: .observation, sources: ["bad": h.base])
        }
    }

    @Test func registrationRejectsOverlapAndPersistsSourceIdentity() throws {
        let h = try Harness(), source = h.base.appendingPathComponent("source")
        let nested = source.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        for roots in [["one": source, "two": source], ["one": source, "two": nested]] {
            #expect(throws: SharedMediaStorageFailure.invalid) {
                try SharedMediaStorageRepository(container: h.container, authorityRoot: h.root,
                    inventoryID: h.inventory, mode: .observation, sources: roots)
            }
        }
        var owner: SharedMediaStorageRepository? = try .init(container: h.container, authorityRoot: h.root,
            inventoryID: h.inventory, mode: .observation, sources: ["one": source])
        #expect(try owner!.snapshot().phase == "observing")
        try FileManager.default.moveItem(at: source, to: h.base.appendingPathComponent("retained-source"))
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
        #expect(throws: SharedMediaStorageFailure.conflict) { try owner!.snapshot() }
        owner = nil
        #expect(throws: SharedMediaStorageFailure.conflict) {
            try SharedMediaStorageRepository(container: h.container, authorityRoot: h.root,
                inventoryID: h.inventory, mode: .observation, sources: ["one": source])
        }
    }

    @Test func qualificationRejectsAnExistingLibrary() throws {
        let h = try Harness(), context = ModelContext(h.container)
        context.insert(LocalScanRecord(id: UUID().uuidString, speciesId: "synthetic",
            scientificName: "Fixture", commonName: "Fixture"))
        try context.save()
        #expect(throws: SharedMediaStorageFailure.conflict) { try h.owner() }
        #expect(try !SharedMediaStorageRepository.hasLiabilities(in: ModelContext(h.container)))
    }

    @Test func survivingReferencesAndOpenLeasesPreventRetirement() throws {
        let h = try Harness(), owner = try h.owner(), request = h.reservation(bytes: 1)
        var snapshot = try owner.reserve(request, expected: try owner.snapshot())
        let first = UUID(), second = UUID(), lease = UUID()
        snapshot = try owner.acquireReference(id: first, allocationID: request.id, accountID: request.accountID,
            ownerID: "version-a", role: "source", expected: snapshot)
        snapshot = try owner.acquireReference(id: second, allocationID: request.id, accountID: request.accountID,
            ownerID: "version-b", role: "source", expected: snapshot)
        snapshot = try owner.releaseReference(id: first, expected: snapshot)
        #expect(throws: SharedMediaStorageFailure.inUse) { try owner.retire(allocationID: request.id, expected: snapshot) }
        snapshot = try owner.startLocalLease(id: lease, allocationID: request.id, expected: snapshot)
        snapshot = try owner.releaseReference(id: second, expected: snapshot)
        #expect(throws: SharedMediaStorageFailure.inUse) { try owner.retire(allocationID: request.id, expected: snapshot) }
        snapshot = try owner.finishLocalLease(id: lease, expected: snapshot)
        snapshot = try owner.retire(allocationID: request.id, expected: snapshot)
        #expect(throws: SharedMediaStorageFailure.closed) {
            try owner.acquireReference(id: UUID(), allocationID: request.id, accountID: request.accountID,
                ownerID: "late", role: "source", expected: snapshot)
        }
        let row = try #require(ModelContext(h.container).fetch(FetchDescriptor<SharedMediaAllocationRecord>()).first)
        #expect(row.stateRaw == "retiring" && row.reservedBytes == 1)
    }

    @Test func processLossCannotCloseAnUncertainLease() throws {
        let h = try Harness(), request = h.reservation(bytes: 1), lease = UUID()
        var owner: SharedMediaStorageRepository? = try h.owner()
        let reserved = try owner!.reserve(request, expected: try owner!.snapshot())
        let leased = try owner!.startLocalLease(id: lease, allocationID: request.id, expected: reserved)
        owner = nil
        let resumed = try h.owner()
        #expect(try resumed.snapshot() == leased)
        #expect(throws: SharedMediaStorageFailure.conflict) { try resumed.finishLocalLease(id: lease, expected: leased) }
        #expect(throws: SharedMediaStorageFailure.inUse) { try resumed.retire(allocationID: request.id, expected: leased) }
    }

    @Test func staleRevisionAndAccountClosurePreserveOtherOwners() throws {
        let h = try Harness(), owner = try h.owner(), first = h.reservation(bytes: 1), second = h.reservation(bytes: 1)
        let initial = try owner.snapshot()
        var snapshot = try owner.reserve(first, expected: initial)
        #expect(throws: SharedMediaStorageFailure.stale) { try owner.reserve(second, expected: initial) }
        snapshot = try owner.reserve(second, expected: snapshot)
        snapshot = try owner.acquireReference(id: UUID(), allocationID: first.id, accountID: first.accountID,
            ownerID: "first", role: "source", expected: snapshot)
        snapshot = try owner.acquireReference(id: UUID(), allocationID: second.id, accountID: second.accountID,
            ownerID: "second", role: "source", expected: snapshot)
        snapshot = try owner.retireAccountReferences(first.accountID, expected: snapshot)
        snapshot = try owner.retire(allocationID: first.id, expected: snapshot)
        #expect(throws: SharedMediaStorageFailure.inUse) { try owner.retire(allocationID: second.id, expected: snapshot) }
        snapshot = try owner.closeAdmission(expected: snapshot)
        #expect(throws: SharedMediaStorageFailure.closed) { try owner.reserve(h.reservation(bytes: 1), expected: snapshot) }
        #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<SharedMediaAllocationRecord>()) == 2)
    }

    @Test func observationIsPagedAndNeverGrantsReservationOrErasure() throws {
        let h = try Harness()
        let source = h.base.appendingPathComponent("registered")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
        let tokens = (0..<129).map { "file-\($0)" }
        for token in tokens { try Data([1]).write(to: source.appendingPathComponent(token)) }
        let owner = try SharedMediaStorageRepository(container: h.container, authorityRoot: h.root,
            inventoryID: h.inventory, mode: .observation, sources: ["registered": source])
        var snapshot = try owner.observe(namespace: "registered", tokens: Array(tokens.prefix(128)), cursor: "128", expected: try owner.snapshot())
        snapshot = try owner.observe(namespace: "registered", tokens: [tokens.last!], cursor: "129", expected: snapshot)
        #expect(snapshot.phase == "observing")
        #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<SharedMediaAllocationRecord>()) == 129)
        #expect(throws: SharedMediaStorageFailure.closed) { try owner.reserve(h.reservation(bytes: 1), expected: snapshot) }
        #expect(throws: SharedMediaStorageFailure.invalid) {
            try owner.observe(namespace: "unregistered", tokens: ["any"], cursor: "", expected: snapshot)
        }
        #expect(throws: SharedMediaStorageFailure.closed) { try owner.retire(allocationID: UUID(), expected: snapshot) }
    }

    @Test func fileObservationRejectsAliasesAndPreservesBytes() throws {
        let h = try Harness(), token = "original"
        let source = h.base.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
        let url = source.appendingPathComponent(token), bytes = Data([1, 2, 3])
        try bytes.write(to: url)
        let owner = try SharedMediaStorageRepository(container: h.container, authorityRoot: h.root,
            inventoryID: h.inventory, mode: .observation, sources: ["registered": source])
        let snapshot = try owner.observe(namespace: "registered", tokens: [token], cursor: "1", expected: try owner.snapshot())
        let item = try #require(ModelContext(h.container).fetch(FetchDescriptor<SharedMediaAllocationRecord>()).first)
        #expect(item.materializedBytes == 3)
        #expect(try Data(contentsOf: url) == bytes)
        try FileManager.default.createSymbolicLink(at: source.appendingPathComponent("alias"), withDestinationURL: url)
        #expect(throws: SharedMediaStorageFailure.self) { try owner.observe(namespace: "registered", tokens: ["alias"], cursor: "2", expected: snapshot) }
        try FileManager.default.linkItem(at: url, to: source.appendingPathComponent("hard"))
        #expect(throws: SharedMediaStorageFailure.self) { try owner.observe(namespace: "registered", tokens: [token], cursor: "2", expected: snapshot) }
        #expect(throws: SharedMediaStorageFailure.invalid) { try owner.observe(namespace: "registered", tokens: ["../original"], cursor: "2", expected: snapshot) }
        #expect(try Data(contentsOf: url) == bytes)
    }

    @Test func orphanedLiabilityBlocksPurgeBeforeAnyCallback() async throws {
        let h = try Harness(), context = ModelContext(h.container)
        context.insert(SharedMediaLeaseRecord(id: UUID(), allocationID: UUID(), processEpoch: UUID(), purposeRaw: "unknown", stateRaw: "unknown"))
        try context.save()
        let defaults = try #require(UserDefaults(suiteName: "sma-fixture-" + UUID().uuidString))
        #expect(try !LibraryMutationInventory.read(from: h.container, userDefaults: defaults).isReady)
        var callback = false
        let result = await ScanLibraryPurgeService.purge(modelContext: context, userDefaults: defaults,
            resetRuntimeState: { callback = true }, erasePhotoPreparation: { callback = true }, eraseReanalysis: { callback = true })
        #expect(!result && !callback)
        #expect(try context.fetchCount(FetchDescriptor<SharedMediaLeaseRecord>()) == 1)
    }

    @Test(arguments: [false, true], [false, true])
    func orphanedInboxRowsBlockPurgeBeforeAnyCallback(handoff: Bool, persisted: Bool) async throws {
        let h = try Harness(), context = ModelContext(h.container)
        context.autosaveEnabled = false
        if handoff {
            context.insert(SharedMediaInboxHandoffRecord(id: UUID(), nonce: UUID(), sourceID: UUID(),
                sourceGeneration: UUID(), sourceRevision: 0, inventoryGeneration: UUID(), expectedInventoryRevision: 0,
                ownerID: UUID(), packageID: UUID(), draftGeneration: UUID(), assetID: UUID(), assetGeneration: UUID(),
                referenceID: UUID(), leaseID: UUID(), sourceHoldID: UUID(), ordinal: 0,
                byteCount: 1, sha256: String(repeating: "a", count: 64), writerEpoch: UUID()))
        } else {
            context.insert(SharedMediaInboxSourceRecord(id: UUID(), inventoryID: UUID(), generation: UUID(),
                receivedAt: Date(), rootIdentity: "fixture", maximumBytes: 1, workID: UUID(), writerEpoch: UUID()))
        }
        if persisted { try context.save() }
        let defaults = try #require(UserDefaults(suiteName: "inbox-purge-fixture-" + UUID().uuidString))
        #expect(try SharedMediaStorageRepository.hasLiabilities(in: context))
        if persisted { #expect(try !LibraryMutationInventory.read(from: h.container, userDefaults: defaults).isReady) }
        var callback = false
        let result = await ScanLibraryPurgeService.purge(modelContext: context, userDefaults: defaults,
            resetRuntimeState: { callback = true }, erasePhotoPreparation: { callback = true }, eraseReanalysis: { callback = true })
        #expect(!result && !callback)
        #expect(try context.fetchCount(FetchDescriptor<SharedMediaInboxSourceRecord>()) == (handoff ? 0 : 1))
        #expect(try context.fetchCount(FetchDescriptor<SharedMediaInboxHandoffRecord>()) == (handoff ? 1 : 0))
    }

    @Test func checkedAccountingPreservesPackageSubpoolAndFreeSpaceLimits() throws {
        let mib = PhotoPreparationPolicy.mib
        var totals = SharedMediaStoragePolicy.Totals()
        for _ in 0..<4 { try totals.include(.init(packageID: UUID(), pool: .durable, materialized: 96 * mib, reserved: 0)) }
        try totals.checkAvailable(256 * mib) // Materialized bytes already reduce physical availability.
        #expect(throws: SharedMediaStorageFailure.capacity) { try totals.include(.init(packageID: UUID(), pool: .durable, materialized: 0, reserved: 1)) }
        var pending = SharedMediaStoragePolicy.Totals()
        let package = UUID()
        try pending.include(.init(packageID: package, pool: .acquisition, materialized: 0, reserved: 96 * mib))
        try pending.include(.init(packageID: package, pool: .preparation, materialized: 0, reserved: 64 * mib))
        try pending.include(.init(packageID: package, pool: .transfer, materialized: 0, reserved: 32 * mib))
        try pending.checkAvailable((256 + 192) * mib)
        #expect(throws: SharedMediaStorageFailure.capacity) { try pending.checkAvailable((256 + 192) * mib - 1) }
        #expect(throws: SharedMediaStorageFailure.capacity) { try pending.include(.init(packageID: package, pool: .transfer, materialized: 0, reserved: 1)) }
        #expect(throws: SharedMediaStorageFailure.invalid) { try SharedMediaStoragePolicy.add(Int64.max, 1) }
        #expect(throws: SharedMediaStorageFailure.invalid) { try SharedMediaStoragePolicy.add(-1, 1) }
    }

    @MainActor
    private struct Harness {
        let base: URL
        let root: URL
        let container: ModelContainer
        let inventory = UUID()
        init(nestedStore: Bool = false) throws {
            base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("sma-fixture-" + UUID().uuidString)
            root = base.appendingPathComponent("authority")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let database = nestedStore ? base.appendingPathComponent("database") : base
            if nestedStore { try FileManager.default.createDirectory(at: database, withIntermediateDirectories: false) }
            let schema = Schema(versionedSchema: CurrentSchema.self)
            container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema,
                url: database.appendingPathComponent("fixture.store"), cloudKitDatabase: .none)])
        }
        func owner(mode: SharedMediaStorageMode = .qualification) throws -> SharedMediaStorageRepository {
            try .init(container: container, authorityRoot: root, inventoryID: inventory, mode: mode)
        }
        func reservation(bytes: Int64) -> SharedMediaStorageReservation {
            .init(id: UUID(), packageID: UUID(), accountID: UUID(), pool: .durable, bytes: bytes)
        }
        // Retain small synthetic SQLite fixtures; never unlink files beneath a live container.
    }
}
