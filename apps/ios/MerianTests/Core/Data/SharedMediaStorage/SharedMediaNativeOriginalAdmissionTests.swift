import CryptoKit
import Darwin
import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Registered native original admission", .serialized)
@MainActor
struct SharedMediaNativeOriginalAdmissionTests {
    @Test func completedOriginalReopensWithoutChangingBytesOrReceipt() async throws {
        let h = try Harness(); defer { h.cleanup() }
        let saved = try h.complete()
        let owner = try h.owner()
        let opened = try await h.open(owner)
        #expect(!opened.requiresRecovery && opened.inventory.revision == 2)
        #expect(try await owner.snapshot() == opened)
        await #expect(throws: SharedMediaStorageFailure.closed) { try await h.open(owner) }
        #expect(await h.drain.shutdown())
        let next = try h.owner(drain: .init())
        #expect(try await h.open(next) == opened)
        #expect(try Data(contentsOf: saved.url) == saved.bytes)
        #expect(try ModelContext(h.container).fetch(FetchDescriptor<SharedMediaAcquisitionReceiptRecord>()).first?.resultData == saved.resultData)
        #expect(await next.invalidateAndAwaitForAccountTransition())
    }

    @Test func retainedOriginalReopensAfterOriginDeletionInFreshContainer() async throws {
        let h = try Harness(); defer { h.cleanup() }
        let saved = try h.complete(), context = ModelContext(h.container); context.autosaveEnabled = false
        let old = try #require(context.fetch(FetchDescriptor<PhotoPreparationRecord>()).first)
        let ref = try #require(context.fetch(FetchDescriptor<PhotoPreparationReference>()).first)
        let destinationID = UUID()
        let destination = try PhotoPreparationRecord(id: destinationID, ownerID: h.ownerID, contractVersion: PhotoPreparationPolicy.contract,
            draftID: destinationID, draftGeneration: UUID(), revision: 0, phaseRaw: "draftOwned",
            supportingContextData: PhotoPreparationPolicy.encodeDraft(contexts: []), allocatedByteCount: Int64(saved.bytes.count), retirementRequested: false)
        destination.accountingTierRaw = "retained"; context.insert(destination)
        let id = UUID(), assetID = ref.assetID
        context.delete(ref)
        for edge in try context.fetch(FetchDescriptor<SharedMediaReferenceRecord>()) { context.delete(edge) }
        context.insert(PhotoPreparationReference(id: id, packageID: destination.id, assetID: assetID, ownerID: h.ownerID,
            roleRaw: "original", ordinal: 0, revision: 0, isLive: true))
        context.insert(SharedMediaReferenceRecord(id: id, allocationID: assetID, accountID: h.ownerID,
            ownerID: id.uuidString.lowercased(), roleRaw: SharedMediaPhotoLedger.namespace, stateRaw: "live", revision: 0))
        context.delete(old)
        for member in try context.fetch(FetchDescriptor<SharedMediaPendingMembershipRecord>()) { context.delete(member) }
        try #require(context.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first).revision += 1
        try context.save()
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let reopened = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema,
            url: h.base.appendingPathComponent("database/ledger.store"), cloudKitDatabase: .none)])
        let owner = try h.owner()
        let result = try await owner.open(container: reopened, authorityRoot: h.authority, photoRoot: h.photo,
            inboxRoot: h.inbox, inventoryID: h.inventoryID)
        #expect(!result.requiresRecovery && result.inventory.revision == 3)
        #expect(try Data(contentsOf: saved.url) == saved.bytes)
        #expect(try ModelContext(reopened).fetch(FetchDescriptor<SharedMediaAcquisitionReceiptRecord>()).first?.resultData == saved.resultData)
        #expect(await h.drain.shutdown())
    }

    @Test(arguments: ["completed", "reserved", "held", "terminal", "mixed"])
    func admissionRequiresExactCurrentAccount(_ shape: String) async throws {
        let h = try Harness(); defer { h.cleanup() }
        if shape == "completed" || shape == "mixed" { _ = try h.complete() }
        else if shape == "reserved" || shape == "held" { try h.pending(held: shape == "held", occupancy: "none") }
        else { _ = try h.initialize() }
        if shape == "terminal" || shape == "mixed" {
            let context = ModelContext(h.container); context.autosaveEnabled = false
            let inventory = try #require(context.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first)
            let row = SharedMediaAcquisitionReceiptRecord(operationID: UUID(), inventoryID: h.inventoryID,
                inventoryGeneration: inventory.generation, ownerID: shape == "mixed" ? UUID() : h.ownerID,
                requestFingerprint: String(repeating: "a", count: 64), packageID: UUID(), assetID: UUID(), requestData: Data())
            row.revision = 2; row.phaseRaw = "terminal"; row.terminalOutcomeRaw = "released"
            row.requestData = nil; row.packageID = nil; row.assetID = nil
            context.insert(row); try context.save()
        }
        let owner = try h.owner(ownerID: shape == "mixed" ? h.ownerID : UUID())
        await #expect(throws: PhotoPreparationFailure.accountChanged) { try await h.open(owner) }
        #expect(h.work.active == 0)
        #expect(await h.drain.shutdown())
    }

    @Test(arguments: ["missing", "bytes", "replacement", "partial", "parent", "symlink", "rootExtra", "unknownLeaf", "membership"])
    func changedOrIncompleteStorageCannotExposeOwner(_ change: String) async throws {
        let h = try Harness(); defer { h.cleanup() }
        let saved = try h.complete()
        switch change {
        case "missing": try FileManager.default.removeItem(at: saved.url)
        case "bytes": try Data([2, 3]).write(to: saved.url)
        case "replacement":
            try FileManager.default.removeItem(at: saved.url); try saved.bytes.write(to: saved.url)
        case "partial": try Data().write(to: URL(fileURLWithPath: saved.url.path + ".partial"))
        case "parent":
            let parent = saved.url.deletingLastPathComponent()
            try FileManager.default.moveItem(at: parent, to: parent.appendingPathExtension("old"))
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
            try saved.bytes.write(to: saved.url)
        case "symlink":
            try FileManager.default.removeItem(at: saved.url)
            try FileManager.default.createSymbolicLink(atPath: saved.url.path, withDestinationPath: "/dev/null")
        case "rootExtra": try Data([1]).write(to: h.photo.appendingPathComponent("unknown"))
        case "unknownLeaf": try Data([1]).write(to: saved.url.deletingLastPathComponent().appendingPathComponent(UUID().uuidString.lowercased()))
        default:
            let context = ModelContext(h.container); context.autosaveEnabled = false
            for row in try context.fetch(FetchDescriptor<SharedMediaPendingMembershipRecord>()) { context.delete(row) }
            try context.save()
        }
        let owner = try h.owner()
        await #expect(throws: (any Error).self) { try await h.open(owner) }
        await #expect(throws: SharedMediaStorageFailure.closed) { try await owner.snapshot() }
        #expect(try ModelContext(h.container).fetch(FetchDescriptor<SharedMediaAcquisitionReceiptRecord>()).first?.resultData == saved.resultData)
        #expect(await h.drain.shutdown())
    }

    @Test(arguments: ["absent", "present", "partial", "parent", "namespace"])
    func retirementAbsenceRequiresExactDirectoriesAndNoPartial(_ shape: String) async throws {
        let h = try Harness(); defer { h.cleanup() }
        let saved = try h.complete(retiring: true)
        if shape != "present" { try FileManager.default.removeItem(at: saved.url) }
        if shape == "partial" { try Data().write(to: URL(fileURLWithPath: saved.url.path + ".partial")) }
        if shape == "parent" || shape == "namespace" {
            let target = shape == "parent" ? saved.url.deletingLastPathComponent() : h.photo.appendingPathComponent("PhotoPreparation")
            try FileManager.default.moveItem(at: target, to: h.base.appendingPathComponent("old-directory"))
            try FileManager.default.createDirectory(at: saved.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        let owner = try h.owner()
        if shape == "absent" || shape == "present" {
            #expect(try await h.open(owner).requiresRecovery)
            #expect(FileManager.default.fileExists(atPath: saved.url.path) == (shape == "present"))
        } else { await #expect(throws: (any Error).self) { try await h.open(owner) } }
        let context = ModelContext(h.container)
        #expect(try context.fetchCount(FetchDescriptor<PhotoPreparationAsset>()) == 1)
        #expect(try context.fetch(FetchDescriptor<SharedMediaAssetReferenceCountRecord>()).first?.liveCount == 0)
        #expect(try context.fetch(FetchDescriptor<SharedMediaAcquisitionReceiptRecord>()).first?.resultData == saved.resultData)
        #expect(await h.drain.shutdown())
    }

    @Test(arguments: [false, true], ["none", "partial", "final"])
    func pendingWorkRemainsRecoveryOnly(_ held: Bool, _ occupancy: String) async throws {
        let h = try Harness(); defer { h.cleanup() }
        try h.pending(held: held, occupancy: occupancy)
        let owner = try h.owner()
        let snapshot = try await h.open(owner)
        #expect(snapshot.requiresRecovery && snapshot.inventory.revision == (held ? 2 : 1))
        let context = ModelContext(h.container)
        #expect(try context.fetchCount(FetchDescriptor<PhotoPreparationAsset>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<PhotoPreparationLease>()) == 1)
        #expect(try context.fetch(FetchDescriptor<SharedMediaAcquisitionReceiptRecord>()).first?.phaseRaw == (held ? "held" : "reserved"))
        #expect(await h.drain.shutdown())
    }

    @Test func registrationAndInvalidationPrecedeAnyOpen() async throws {
        let h = try Harness(); defer { h.cleanup() }
        let owner = try h.owner()
        #expect(throws: SharedMediaStorageFailure.closed) { try h.owner() }
        #expect(await h.drain.shutdown())
        await #expect(throws: SharedMediaStorageFailure.closed) { try await h.open(owner) }
        #expect(throws: SharedMediaStorageFailure.closed) { try h.owner() }
        #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<SharedMediaInventoryRecord>()) == 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: h.photo.path).isEmpty)
    }

    @Test(arguments: ["auth", "caller", "revision"])
    func pausedAdmissionDrainsBeforeReleasingFences(_ action: String) async throws {
        let h = try Harness(); defer { h.cleanup() }
        let owner = try h.owner(), pause = Pause()
        let open = Task { try await h.open(owner, pause: { await pause.hold() }) }
        await pause.waitForEntry()
        await #expect(throws: SharedMediaStorageFailure.closed) { try await h.open(owner) }
        let competitor = try h.owner(drain: .init())
        await #expect(throws: (any Error).self) { try await h.open(competitor) }
        var preparationDone = false, accountDrained = false
        let teardown: Task<Bool, Never>?
        if action == "auth" {
            teardown = Task {
                await SupabaseManager.drainPhotoPreparationBeforeAccountWork(preparation: {
                    let result = await h.drain.shutdown()
                    #expect(h.work.active == 0)
                    preparationDone = true; return result
                }, drain: { await h.runtime.awaitAccountWorkDrain(); accountDrained = true })
            }
        } else {
            teardown = nil
            if action == "caller" { open.cancel() }
            else {
                let context = ModelContext(h.container); context.autosaveEnabled = false
                let row = try #require(context.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first)
                row.revision += 1; try context.save()
            }
        }
        await Task.yield()
        #expect(!preparationDone && !accountDrained)
        let stillCompeting = try h.owner(drain: .init())
        await #expect(throws: (any Error).self) { try await h.open(stillCompeting) }
        await pause.release()
        if let teardown {
            #expect(await teardown.value); #expect(preparationDone && accountDrained)
            #expect(h.work.active == 0)
            let immediate = try h.owner(drain: .init())
            _ = try await h.open(immediate)
            #expect(await immediate.invalidateAndAwaitForAccountTransition())
        }
        await #expect(throws: (any Error).self) { try await open.value }
        if teardown == nil { #expect(await h.drain.shutdown()) }
        #expect(h.work.active == 0)
        await #expect(throws: SharedMediaStorageFailure.closed) { try await owner.snapshot() }
        let reopened = try h.owner(drain: .init())
        _ = try await h.open(reopened)
        #expect(await reopened.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["orphan", "replacement", "partial", "rootExtra"])
    func changesAfterReverseHashCannotEscapeFinalStream(_ change: String) async throws {
        let h = try Harness(); defer { h.cleanup() }
        let saved = try h.complete(), owner = try h.owner(), pause = Pause(after: 2)
        let open = Task { try await h.open(owner, pause: { await pause.hold() }) }
        await pause.waitForEntry()
        switch change {
        case "orphan": try Data([1]).write(to: saved.url.deletingLastPathComponent().appendingPathComponent(UUID().uuidString.lowercased()))
        case "replacement":
            try FileManager.default.moveItem(at: saved.url, to: h.base.appendingPathComponent("old-original"))
            try saved.bytes.write(to: saved.url)
        case "partial": try Data().write(to: URL(fileURLWithPath: saved.url.path + ".partial"))
        default: try Data([1]).write(to: h.photo.appendingPathComponent("unknown"))
        }
        await pause.release()
        await #expect(throws: (any Error).self) { try await open.value }
        await #expect(throws: SharedMediaStorageFailure.closed) { try await owner.snapshot() }
        #expect(await h.drain.shutdown())
        #expect(try ModelContext(h.container).fetch(FetchDescriptor<SharedMediaAcquisitionReceiptRecord>()).first?.resultData == saved.resultData)
    }

    @MainActor private final class WorkCount { var active = 0 }

    private actor Pause {
        private let after: Int
        private var calls = 0
        private var entered = false, released = false
        private var waiting: CheckedContinuation<Void, Never>?
        private var entry: CheckedContinuation<Void, Never>?
        init(after: Int = 1) { self.after = after }
        func hold() async {
            calls += 1
            if calls < after { return }
            if released { return }
            await withCheckedContinuation { waiting = $0; entered = true; entry?.resume(); entry = nil }
        }
        func waitForEntry() async {
            if entered { return }
            await withCheckedContinuation { entry = $0 }
        }
        func release() { released = true; waiting?.resume(); waiting = nil }
    }

    private struct Saved {
        let url: URL, bytes: Data, resultData: Data
    }

    @MainActor private struct Harness {
        let base: URL, authority: URL, photo: URL, inbox: URL
        let inventoryID = UUID(), ownerID = UUID()
        let container: ModelContainer
        let runtime = AuthRuntimeState(), drain = SharedMediaNativeOriginalDrain()
        let work = WorkCount()
        init() throws {
            base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("native-original-admission-" + UUID().uuidString)
            authority = base.appendingPathComponent("authority"); photo = base.appendingPathComponent("photo"); inbox = base.appendingPathComponent("inbox")
            let database = base.appendingPathComponent("database")
            for root in [authority, photo, inbox, database] { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
            let schema = Schema(versionedSchema: CurrentSchema.self)
            container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: database.appendingPathComponent("ledger.store"), cloudKitDatabase: .none)])
        }
        func owner(drain: SharedMediaNativeOriginalDrain? = nil, ownerID: UUID? = nil) throws -> SharedMediaNativeOriginalOwner {
            let account = PhotoOriginalPreparationOwner.syntheticAccount(ownerID: ownerID ?? self.ownerID, runtime: runtime)
            return try .qualification(account: .init(ownerID: account.ownerID,
                begin: { let lease = try account.begin(); work.active += 1; return lease },
                isCurrent: account.isCurrent, finish: { account.finish($0); work.active -= 1 }), drain: drain ?? self.drain)
        }
        func open(_ owner: SharedMediaNativeOriginalOwner, pause: (@Sendable () async -> Void)? = nil) async throws -> SharedMediaNativeOriginalSnapshot {
            try await owner.open(container: container, authorityRoot: authority, photoRoot: photo, inboxRoot: inbox, inventoryID: inventoryID, pause: pause)
        }
        func initialize() throws -> SharedMediaStorageSnapshot {
            let owner = try SharedMediaNativeStorageRepository.qualification(container: container, authorityRoot: authority,
                photoRoot: photo, inboxRoot: inbox, inventoryID: inventoryID)
            return try owner.snapshot()
        }
        func intent(_ snapshot: SharedMediaStorageSnapshot) -> SharedMediaAcquisitionIntent {
            .init(operationID: UUID(), inventoryID: inventoryID, inventoryGeneration: snapshot.generation, ownerID: ownerID,
                expectedInventoryRevision: 0, packageID: UUID(), draftGeneration: UUID(), packageExpectation: .absent,
                assetID: UUID(), assetGeneration: UUID(), referenceID: UUID(), ordinal: 0, kind: .picker, writerEpoch: UUID(), maximumBytes: PhotoPreparationPolicy.original)
        }
        func package(_ r: SharedMediaAcquisitionIntent, phase: String, revision: Int64, bytes: Int64) throws -> PhotoPreparationRecord {
            try .init(id: r.packageID, ownerID: ownerID, contractVersion: PhotoPreparationPolicy.contract, draftID: r.packageID,
                draftGeneration: r.draftGeneration, revision: revision, phaseRaw: phase, supportingContextData: PhotoPreparationPolicy.encodeDraft(contexts: []), allocatedByteCount: bytes, retirementRequested: false)
        }
        func receipt(_ r: SharedMediaAcquisitionIntent) throws -> SharedMediaAcquisitionReceiptRecord {
            try .init(operationID: r.operationID, inventoryID: inventoryID, inventoryGeneration: r.inventoryGeneration, ownerID: ownerID,
                requestFingerprint: r.fingerprint(), packageID: r.packageID, assetID: r.assetID, requestData: r.encoded())
        }
        func file(_ r: SharedMediaAcquisitionIntent) throws -> URL {
            let url = photo.appendingPathComponent("PhotoPreparation").appendingPathComponent(r.finalToken)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            return url
        }
        func pending(held: Bool, occupancy: String) throws {
            let r = intent(try initialize()), context = ModelContext(container); context.autosaveEnabled = false
            let inventory = try #require(context.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first)
            inventory.revision = held ? 2 : 1
            let draft = try package(r, phase: held ? "needsAttention" : "acquiring", revision: held ? 1 : 0, bytes: 0)
            context.insert(draft)
            let row = try receipt(r); if held { row.phaseRaw = "held"; row.revision = 1 }; context.insert(row)
            context.insert(SharedMediaAllocationRecord(id: r.assetID, inventoryID: inventoryID, accountID: ownerID, packageID: r.packageID,
                namespaceRaw: SharedMediaPhotoLedger.namespace, fileToken: r.finalToken, poolRaw: "durable", stateRaw: held ? "p1Held" : "p1Reserved", materializedBytes: 0, reservedBytes: r.maximumBytes, physicalIdentity: nil))
            context.insert(SharedMediaLeaseRecord(id: r.operationID, allocationID: r.assetID, processEpoch: r.writerEpoch, purposeRaw: "p1AcquireV1", stateRaw: held ? "unknown" : "open"))
            context.insert(PhotoPreparationLease(id: r.operationID, packageID: r.packageID, assetID: r.assetID, ownerID: ownerID,
                processEpoch: r.writerEpoch, purposeRaw: "acquire", partialFileToken: r.partialToken, finalFileToken: r.finalToken,
                reservedByteCount: r.maximumBytes, allocatedByteCount: 0, writerStateRaw: held ? "unknown" : "open", terminalProof: nil))
            try membership(context, inventory: inventory, draft: draft, revision: 0); try context.save()
            if occupancy != "none" {
                let url = try file(r)
                if occupancy == "partial" { try Data().write(to: URL(fileURLWithPath: url.path + ".partial")) }
                else { try Data([1]).write(to: url) }
            }
        }
        func complete(retiring: Bool = false) throws -> Saved {
            let r = intent(try initialize()), context = ModelContext(container); context.autosaveEnabled = false
            let inventory = try #require(context.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first); inventory.revision = 2
            let url = try file(r), bytes = PhotoPreparationTestHarness.image(); try bytes.write(to: url)
            let identity = try proof(url)
            let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            let result = try SharedMediaAcquisitionResult(request: r, inventoryRevision: 2, packageRevision: 1, membershipRevision: 1,
                byteCount: Int64(bytes.count), sha256: digest, contentType: "public.jpeg", descriptor: identity)
            let data = try result.encoded(request: r), row = try receipt(r)
            row.phaseRaw = "completed"; row.revision = 1; row.resultData = data; context.insert(row)
            let draft = try package(r, phase: "draftOwned", revision: 1, bytes: Int64(bytes.count)); context.insert(draft)
            let counter = SharedMediaAssetReferenceCountRecord(assetID: r.assetID, assetGeneration: r.assetGeneration,
                inventoryID: inventoryID, inventoryGeneration: r.inventoryGeneration, ownerID: ownerID, liveCount: retiring ? 0 : 1)
            let retirement = try SharedMediaNativeRetirementIdentity(retirementID: UUID(), assetID: r.assetID, assetGeneration: r.assetGeneration,
                inventoryID: inventoryID, inventoryGeneration: r.inventoryGeneration, ownerID: ownerID, proof: identity)
            if retiring { counter.retirementID = retirement.retirementID; counter.revision = 1 }
            context.insert(counter)
            context.insert(PhotoPreparationAsset(id: r.assetID, ownerID: ownerID, generation: r.assetGeneration, fileToken: r.finalToken,
                contentType: result.contentType, byteCount: result.byteCount, sha256: digest, acquisitionKindRaw: "picker", cleanupStateRaw: retiring ? "retiring" : "ready"))
            context.insert(SharedMediaAllocationRecord(id: r.assetID, inventoryID: inventoryID, accountID: ownerID, packageID: r.packageID,
                namespaceRaw: SharedMediaPhotoLedger.namespace, fileToken: r.finalToken, poolRaw: "durable", stateRaw: retiring ? SharedMediaNativeRetirementIdentity.allocationState : "p1Materialized",
                materializedBytes: result.byteCount, reservedBytes: 0, physicalIdentity: retiring ? try retirement.encoded() : identity.file))
            context.insert(SharedMediaLeaseRecord(id: r.operationID, allocationID: r.assetID, processEpoch: r.writerEpoch, purposeRaw: "p1AcquireV1", stateRaw: "closed"))
            context.insert(PhotoPreparationReference(id: r.referenceID, packageID: r.packageID, assetID: r.assetID, ownerID: ownerID,
                roleRaw: "original", ordinal: 0, revision: retiring ? 1 : 0, isLive: !retiring))
            context.insert(SharedMediaReferenceRecord(id: r.referenceID, allocationID: r.assetID, accountID: ownerID, ownerID: r.referenceID.uuidString.lowercased(),
                roleRaw: SharedMediaPhotoLedger.namespace, stateRaw: retiring ? "retired" : "live", revision: retiring ? 1 : 0))
            try membership(context, inventory: inventory, draft: draft, revision: 1); try context.save()
            return .init(url: url, bytes: bytes, resultData: data)
        }
        func membership(_ context: ModelContext, inventory: SharedMediaInventoryRecord, draft: PhotoPreparationRecord, revision: Int64) throws {
            let graph = try SharedMediaPendingGraph.derive(in: context, inventory: inventory)
            let member = try SharedMediaPendingMembershipRecord(packageID: draft.id, inventoryID: inventoryID, inventoryGeneration: inventory.generation,
                ownerID: ownerID, draftGeneration: draft.draftGeneration, membersData: graph.membership(packageID: draft.id).encoded())
            member.revision = revision; context.insert(member)
        }
        func proof(_ url: URL) throws -> SharedMediaPhotoRetirementIdentity {
            var file = stat(), parent = stat(), namespace = stat()
            guard lstat(url.path, &file) == 0, lstat(url.deletingLastPathComponent().path, &parent) == 0,
                  lstat(photo.appendingPathComponent("PhotoPreparation").path, &namespace) == 0 else { throw PhotoPreparationFailure.unavailable }
            return .init(version: 1, file: "\(file.st_dev):\(file.st_ino):\(file.st_size):\(file.st_mtimespec.tv_sec):\(file.st_mtimespec.tv_nsec):\(file.st_ctimespec.tv_sec):\(file.st_ctimespec.tv_nsec)",
                parent: "\(parent.st_dev):\(parent.st_ino)", namespace: "\(namespace.st_dev):\(namespace.st_ino)")
        }
        func cleanup() { try? FileManager.default.removeItem(at: base) }
    }
}
