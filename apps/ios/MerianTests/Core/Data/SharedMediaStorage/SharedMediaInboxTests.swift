import Darwin
import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Isolated durable source inbox", .serialized)
@MainActor
struct SharedMediaInboxTests {
    enum Fault: Error { case injected }

    @Test func exactOriginalSurvivesReopenWithoutLegacyCatalog() async throws {
        let h = try Harness(), bytes = PhotoPreparationTestHarness.image()
        var owner: SharedMediaInboxOwner? = try h.owner()
        let handle = try await owner!.stage { bytes }
        #expect(try await owner!.originalData(handle) == bytes)
        #expect(try owner!.catalog() == [handle])
        #expect(try FileManager.default.contentsOfDirectory(atPath: h.inbox.path) == ["InboxSources"])
        let context = ModelContext(h.container)
        let source = try #require(context.fetch(FetchDescriptor<SharedMediaInboxSourceRecord>()).first)
        #expect(source.writerStateRaw == "closed" && source.byteCount == bytes.count && source.partialInode != nil)
        #expect(try context.fetch(FetchDescriptor<SharedMediaReferenceRecord>()).allSatisfy { $0.accountID == nil && $0.stateRaw == "unassigned" })
        owner = nil
        let reopened = try h.owner()
        #expect(try await reopened.recover() == [.ready(handle)])
        #expect(try await reopened.originalData(handle) == bytes)
    }

    @Test(arguments: [SharedMediaInboxBoundary.afterReservationSave, .afterPreparedSave, .afterIdentitySave, .afterCompletionSave])
    func exactReadbackResolvesLostAcknowledgements(_ point: SharedMediaInboxBoundary) async throws {
        let h = try Harness(), owner = try h.owner(), calls = Calls(), bytes = PhotoPreparationTestHarness.image()
        owner.setFault { if $0 == point { throw Fault.injected } }
        let handle = try await owner.stage { await calls.hit(); return bytes }
        #expect(await calls.count == 1)
        #expect(try await owner.originalData(handle) == bytes)
    }

    @Test func reservationFailureNeverLoadsOrWritesSource() async throws {
        let h = try Harness(), owner = try h.owner(), calls = Calls()
        owner.setFault { if $0 == .beforeReservationSave { throw Fault.injected } }
        await #expect(throws: (any Error).self) { try await owner.stage { await calls.hit(); return Data() } }
        #expect(await calls.count == 0)
        #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<SharedMediaInboxSourceRecord>()) == 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: h.namespace.path).isEmpty)
    }

    @Test(arguments: [SharedMediaInboxBoundary.afterRename, .duringWrite])
    func retainedInodeAndPreparedFactsRecoverOriginalWrite(_ point: SharedMediaInboxBoundary) async throws {
        let h = try Harness(), calls = Calls(), bytes = PhotoPreparationTestHarness.image()
        var owner: SharedMediaInboxOwner? = try h.owner()
        await owner!.setFileFault { if $0 == point { throw Fault.injected } }
        await #expect(throws: (any Error).self) { try await owner!.stage { await calls.hit(); return bytes } }
        owner = nil
        let reopened = try h.owner(), result = try await reopened.recover()
        // The tiny fixture fits in its first chunk; its complete partial is
        // verified and renamed, with no second source callback.
        guard case .ready(let handle) = try #require(result.first) else { Issue.record("Expected original-operation recovery"); return }
        #expect(try await reopened.originalData(handle) == bytes)
        #expect(await calls.count == 1)
    }

    @Test(arguments: [nil, .beforeOccupancySave, .afterOccupancySave] as [SharedMediaInboxBoundary?])
    func interruptedPartialCountsOccupiedAndOutstandingBytesOnce(loseOccupancySave: SharedMediaInboxBoundary?) async throws {
        let h = try Harness()
        var data = PhotoPreparationTestHarness.image()
        data.append(Data(repeating: 0, count: 131_072))
        let bytes = data
        var owner: SharedMediaInboxOwner? = try h.owner()
        await owner!.setFileFault { if $0 == .duringWrite { throw Fault.injected } }
        if let loseOccupancySave { owner!.setFault { if $0 == loseOccupancySave { throw Fault.injected } } }
        await #expect(throws: (any Error).self) { try await owner!.stage { bytes } }
        owner = nil
        let reopened = try h.owner()
        let result = try await reopened.recover()
        guard case .incomplete(let handle) = try #require(result.first) else { Issue.record("Expected incomplete original write"); return }
        let context = ModelContext(h.container)
        let allocation = try #require(context.fetch(FetchDescriptor<SharedMediaAllocationRecord>()).first)
        #expect(allocation.materializedBytes == 65_536)
        #expect(allocation.reservedBytes == Int64(bytes.count) - 65_536)
        #expect(allocation.materializedBytes + allocation.reservedBytes == Int64(bytes.count))
        #expect(try FileManager.default.attributesOfItem(atPath: h.namespace.appendingPathComponent(handle.id.uuidString.lowercased() + ".partial").path)[.size] as? Int == 65_536)
        try await reopened.discard(handle)
        #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<SharedMediaAllocationRecord>()) == 0)
    }

    @Test func missingPartialIdentityRemainsConflictWithoutAdoption() async throws {
        let h = try Harness(), bytes = PhotoPreparationTestHarness.image()
        var owner: SharedMediaInboxOwner? = try h.owner()
        owner!.setFault { if $0 == .beforeIdentitySave { throw Fault.injected } }
        await #expect(throws: (any Error).self) { try await owner!.stage { bytes } }
        owner = nil
        let reopened = try h.owner(), result = try await reopened.recover()
        guard case .conflict(let handle) = try #require(result.first) else { Issue.record("Unidentified partial must stay held"); return }
        await #expect(throws: (any Error).self) { try await reopened.discard(handle) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: h.namespace.path).count == 1)
        #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<SharedMediaInboxSourceRecord>()) == 1)
    }

    @Test func unfinishedSourcesConsumeHeadroomBeforeAnyNewCallback() async throws {
        let h = try Harness(), owner = try h.owner(), calls = Calls()
        for _ in 0..<2 {
            await #expect(throws: (any Error).self) { try await owner.stage { throw Fault.injected } }
        }
        await #expect(throws: (any Error).self) { try await owner.stage { await calls.hit(); return Data() } }
        #expect(await calls.count == 0)
        let context = ModelContext(h.container)
        #expect(try context.fetchCount(FetchDescriptor<SharedMediaInboxSourceRecord>()) == 2)
        let recovery = try await owner.recover()
        guard case .incomplete(let handle) = try #require(recovery.first) else { Issue.record("Expected retained reservation"); return }
        try await owner.discard(handle)
        let bytes = PhotoPreparationTestHarness.image()
        _ = try await owner.stage { await calls.hit(); return bytes }
        #expect(await calls.count == 1)
    }

    @Test(arguments: [SharedMediaInboxBoundary.afterRetirementSave, .afterReleaseSave])
    func retirementSaveAcknowledgementsDoNotLeakRows(_ point: SharedMediaInboxBoundary) async throws {
        let h = try Harness(), owner = try h.owner(), bytes = PhotoPreparationTestHarness.image()
        let handle = try await owner.stage { bytes }
        owner.setFault { if $0 == point { throw Fault.injected } }
        try await owner.discard(handle)
        let context = ModelContext(h.container)
        #expect(try context.fetchCount(FetchDescriptor<SharedMediaInboxSourceRecord>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<SharedMediaAllocationRecord>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<SharedMediaReferenceRecord>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<SharedMediaLeaseRecord>()) == 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: h.namespace.path).isEmpty)
        await #expect(throws: (any Error).self) { try await owner.discard(handle) }
    }

    @Test func unlinkCrashRecoversSavedIntentAndPreservesOtherOriginal() async throws {
        let h = try Harness(), bytes = PhotoPreparationTestHarness.image()
        var owner: SharedMediaInboxOwner? = try h.owner()
        let first = try await owner!.stage { bytes }, second = try await owner!.stage { bytes }
        await owner!.setFileFault { if $0 == .afterFinalUnlink { throw Fault.injected } }
        await #expect(throws: (any Error).self) { try await owner!.discard(first) }
        owner = nil
        let reopened = try h.owner()
        #expect(try await reopened.recover() == [.ready(second)])
        #expect(try await reopened.originalData(second) == bytes)
        #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<SharedMediaInboxSourceRecord>()) == 1)
    }

    @Test func changedOriginalUnknownEntryAndHardlinkBlockDeletion() async throws {
        let h = try Harness(), owner = try h.owner(), bytes = PhotoPreparationTestHarness.image()
        let handle = try await owner.stage { bytes }, url = h.namespace.appendingPathComponent(handle.id.uuidString.lowercased())
        let unknown = h.namespace.appendingPathComponent("unknown")
        try Data([1]).write(to: unknown)
        await #expect(throws: (any Error).self) { try await owner.discard(handle) }
        #expect(FileManager.default.fileExists(atPath: url.path))
        try FileManager.default.removeItem(at: unknown)
        let alias = h.base.appendingPathComponent("alias")
        try FileManager.default.linkItem(at: url, to: alias)
        await #expect(throws: (any Error).self) { try await owner.discard(handle) }
        try FileManager.default.removeItem(at: alias)
        try Data([1, 2]).write(to: url)
        await #expect(throws: (any Error).self) { try await owner.discard(handle) }
        #expect(try Data(contentsOf: url) == Data([1, 2]))
    }

    @Test func legacyImportCannotReadAdoptOrEraseBoundNamespace() async throws {
        let h = try Harness(), bytes = PhotoPreparationTestHarness.image()
        var owner: SharedMediaInboxOwner? = try h.owner()
        let handle = try await owner!.stage { bytes }
        owner = nil
        for root in [h.inbox, h.namespace] {
            let legacy = ExternalImageImportStore(rootURL: root)
            #expect(await legacy.pendingImports().isEmpty)
            let pending = PendingExternalImageImport(id: handle.id, storedFilename: handle.id.uuidString.lowercased(), receivedAt: Date())
            #expect(await legacy.fileURL(for: pending) == nil)
            await legacy.remove(pending)
            await #expect(throws: (any Error).self) { try await legacy.stageIncomingImage(at: h.namespace.appendingPathComponent(pending.storedFilename)) }
        }
        #expect(try await h.owner().originalData(handle) == bytes)
    }

    @Test func markedRootRejectsStaleMissingFileError() throws {
        let h = try Harness()
        var owner: SharedMediaInboxOwner? = try h.owner()
        #expect(owner != nil)
        owner = nil
        errno = ENOENT
        #expect(throws: (any Error).self) {
            try SharedMediaInboxLegacyFence(root: h.inbox, createIfMissing: true)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: h.inbox.path) == ["InboxSources"])
    }

    @Test func symlinkedAncestorCannotCreateDescendantInBoundInbox() throws {
        let h = try Harness()
        var owner: SharedMediaInboxOwner? = try h.owner()
        #expect(owner != nil)
        owner = nil
        let alias = h.base.appendingPathComponent("inbox-alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: h.inbox)
        #expect(throws: (any Error).self) {
            try SharedMediaInboxLegacyFence(root: alias.appendingPathComponent("missing/child"), createIfMissing: true)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: h.inbox.path) == ["InboxSources"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: h.namespace.path).isEmpty)
    }

    @Test func cancellationRetainsFenceUntilProviderActuallyReturns() async throws {
        let h = try Harness(), owner = try h.owner(), gate = Gate(), bytes = PhotoPreparationTestHarness.image()
        let work = Task { try await owner.stage { await gate.wait(); return bytes } }
        await gate.started()
        let drain = Task { await owner.suspendAndDrain() }
        await Task.yield()
        #expect(throws: (any Error).self) { try h.owner() }
        await gate.release()
        _ = await work.result; await drain.value
        #expect(try ModelContext(h.container).fetch(FetchDescriptor<SharedMediaInboxSourceRecord>()).first?.writerStateRaw == "closed")
    }

    @MainActor private struct Harness {
        let base: URL, authority: URL, inbox: URL, photo: URL, namespace: URL
        let container: ModelContainer
        let inventory = UUID()
        init() throws {
            base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("shared-inbox-" + UUID().uuidString)
            authority = base.appendingPathComponent("authority"); inbox = base.appendingPathComponent("inbox")
            photo = base.appendingPathComponent("photo"); namespace = inbox.appendingPathComponent("InboxSources")
            let db = base.appendingPathComponent("database")
            for root in [authority, inbox, photo, db] { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
            let schema = Schema(versionedSchema: CurrentSchema.self)
            container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: db.appendingPathComponent("ledger.store"), cloudKitDatabase: .none)])
        }
        func owner() throws -> SharedMediaInboxOwner {
            try .init(container: container, authorityRoot: authority, inboxRoot: inbox, photoRoot: photo, inventoryID: inventory)
        }
    }
    private actor Calls {
        var count = 0
        func hit() { count += 1 }
    }
    private actor Gate {
        var began = false
        var continuation: CheckedContinuation<Void, Never>?
        func wait() async { began = true; await withCheckedContinuation { continuation = $0 } }
        func started() async { while !began { await Task.yield() } }
        func release() { continuation?.resume(); continuation = nil }
    }
}
