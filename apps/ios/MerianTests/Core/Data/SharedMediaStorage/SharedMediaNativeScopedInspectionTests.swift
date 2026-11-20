import Darwin
import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Scoped native existing-profile inspection", .serialized)
@MainActor
struct SharedMediaNativeScopedInspectionTests {
    @Test func exactExistingProfileOpensWithoutDispatchOrAdoptingOrdinaryDrafts() async throws {
        let h = try Store()
        try h.ordinaryDraft()
        let owner = try h.owner(), before = try h.markerBytes()
        let result = try await h.open(owner)
        #expect(result.pendingPackages == 0 && result.receipts == 0 && result.allocations == 0)
        #expect(try await owner.inspectScoped() == result)
        await #expect(throws: (any Error).self) { _ = try await owner.snapshot() }
        await #expect(throws: (any Error).self) {
            _ = try await owner.prepareOriginal(packageID: UUID(), draftGeneration: UUID(), ordinal: 0, kind: .picker)
        }
        #expect(try h.markerBytes() == before)
        #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<PhotoPreparationRecord>()) == 1)
        #expect(await h.drain.shutdown())
    }

    @Test(arguments: ["authority", "photo", "inbox", "fence", "namespace", "backup", "profile", "bootstrap"])
    func missingPrerequisiteIsNeverInitializedOrRepaired(_ missing: String) async throws {
        let h = try Store()
        if let entry = h.markers.first(where: { $0.0 == missing }) {
            #expect(removexattr(entry.1.path, entry.2, 0) == 0)
        } else if missing == "fence" { try FileManager.default.removeItem(at: h.fence) }
        else if missing == "namespace" { try FileManager.default.removeItem(at: h.photo.appendingPathComponent("PhotoPreparation")) }
        else if missing == "backup" {
            var url = h.photo, values = URLResourceValues(); values.isExcludedFromBackup = false; try url.setResourceValues(values)
        } else {
            let context = ModelContext(h.container); context.autosaveEnabled = false
            if missing == "profile" {
                let row = try #require(try context.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first)
                row.modeRaw = "nativeQualificationV1"
            } else {
                let row = try #require(try context.fetch(FetchDescriptor<SharedMediaMembershipBootstrapRecord>()).first)
                context.delete(row)
            }
            try context.save()
        }
        let before = try h.markerBytes(), owner = try h.owner()
        await #expect(throws: (any Error).self) { _ = try await h.open(owner) }
        await #expect(throws: (any Error).self) { _ = try await owner.inspectScoped() }
        #expect(try h.markerBytes() == before)
        if missing == "fence" { #expect(!FileManager.default.fileExists(atPath: h.fence.path)) }
        if missing == "namespace" { #expect(!FileManager.default.fileExists(atPath: h.photo.appendingPathComponent("PhotoPreparation").path)) }
        #expect(await h.drain.shutdown())
    }

    @Test func qualificationCannotOpenOrConvertScopedRoots() async throws {
        let h = try Store(), before = try h.markerBytes()
        let owner = try SharedMediaNativeOriginalOwner.qualification(account: h.account, drain: .init())
        await #expect(throws: (any Error).self) {
            _ = try await owner.open(container: h.container, authorityRoot: h.authority, photoRoot: h.photo,
                inboxRoot: h.inbox, inventoryID: h.inventoryID)
        }
        #expect(try h.markerBytes() == before)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func accountDrainRetainsFenceUntilPausedInspectionActuallyReturns() async throws {
        let h = try Store(), gate = Gate(), owner = try h.owner()
        let opening = Task { @MainActor in
            do { let result = try await h.open(owner, pause: { await gate.pause() }); await gate.finished(); return result }
            catch { await gate.finished(); throw error }
        }
        guard await gate.entered() else { _ = try await opening.value; Issue.record("Inspection did not reach its page boundary"); return }
        var drained = false
        let shutdown = Task { @MainActor in let result = await h.drain.shutdown(); drained = true; return result }
        await Task.yield()
        #expect(!drained)
        let other = try h.owner(drain: .init())
        await #expect(throws: (any Error).self) { _ = try await h.open(other) }
        await gate.release()
        await #expect(throws: (any Error).self) { _ = try await opening.value }
        #expect(await shutdown.value)
        #expect(await other.invalidateAndAwaitForAccountTransition())
        let reopened = try h.owner(drain: .init()); _ = try await h.open(reopened)
        #expect(await reopened.invalidateAndAwaitForAccountTransition())
    }

    @Test func laterPageRevisionChangeReturnsNoPartialResult() async throws {
        let h = try Store(); try h.terminalReceipts(SharedMediaStoragePolicy.pageSize + 1)
        let gate = Gate(), owner = try h.owner()
        let opening = Task { @MainActor in
            do { let result = try await h.open(owner, pause: { await gate.pause() }); await gate.finished(); return result }
            catch { await gate.finished(); throw error }
        }
        guard await gate.entered() else { _ = try await opening.value; Issue.record("Inspection did not reach its page boundary"); return }
        let context = ModelContext(h.container); context.autosaveEnabled = false
        let row = try #require(try context.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first)
        row.revision += 1; try context.save()
        await gate.release()
        await #expect(throws: (any Error).self) { _ = try await opening.value }
        #expect(await h.drain.shutdown())
        let next = try h.owner(drain: .init()), result = try await h.open(next)
        #expect(result.receipts == Int64(SharedMediaStoragePolicy.pageSize + 1))
        #expect(await next.invalidateAndAwaitForAccountTransition())
    }

    private actor Gate {
        var didEnter = false, didFinish = false, released = false
        var arrival: CheckedContinuation<Bool, Never>?
        var waiting: CheckedContinuation<Void, Never>?
        func pause() async {
            guard !released else { return }; didEnter = true; arrival?.resume(returning: true); arrival = nil
            await withCheckedContinuation { waiting = $0 }
        }
        func entered() async -> Bool {
            if didEnter { return true }; if didFinish { return false }
            return await withCheckedContinuation { arrival = $0 }
        }
        func finished() { didFinish = true; arrival?.resume(returning: didEnter); arrival = nil }
        func release() { released = true; waiting?.resume(); waiting = nil }
    }

    /// Synthetic already-initialized profile, not a production bootstrap API.
    @MainActor private struct Store {
        let base: URL, authority: URL, photo: URL, inbox: URL, fence: URL
        let container: ModelContainer
        let inventoryID = UUID(), generation = UUID(), ownerID = UUID()
        let runtime = AuthRuntimeState(), drain = SharedMediaNativeOriginalDrain()
        var account: PhotoOriginalPreparationOwner.AccountAccess { PhotoOriginalPreparationOwner.syntheticAccount(ownerID: ownerID, runtime: runtime) }
        var markers: [(String, URL, String)] { [("authority", authority, "com.merian.shared-media-store-v1"),
            ("photo", photo, "com.merian.p1-shared-v1"), ("inbox", inbox, SharedMediaInboxFiles.marker)] }
        init() throws {
            base = URL.applicationSupportDirectory.resolvingSymlinksInPath().appendingPathComponent("scoped-native-test-" + UUID().uuidString)
            authority = base.appendingPathComponent("authority"); photo = base.appendingPathComponent("photo"); inbox = base.appendingPathComponent("inbox")
            let database = base.appendingPathComponent("database")
            for root in [authority, photo, inbox, database] {
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                var url = root, values = URLResourceValues(); values.isExcludedFromBackup = true; try url.setResourceValues(values)
            }
            for url in [photo.appendingPathComponent("PhotoPreparation"), inbox.appendingPathComponent("InboxSources")] {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            }
            let schema = Schema(versionedSchema: CurrentSchema.self)
            container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema,
                url: database.appendingPathComponent("ledger.store"), cloudKitDatabase: .none)])
            fence = database.appendingPathComponent(SharedMediaStoreReadFence.name)
            guard FileManager.default.createFile(atPath: fence.path, contents: Data(), attributes: [.posixPermissions: 0o600]) else {
                throw SharedMediaStorageFailure.unavailable
            }
            let rootBinding = try SharedMediaStorageLookup.binding(authority: SharedMediaStorageFileOwner.directoryIdentity(authority),
                sources: [SharedMediaPhotoLedger.namespace: photo, SharedMediaInboxFiles.namespace: inbox])
            let store = try SharedMediaNativeEligibility.storeIdentity(at: database.appendingPathComponent("ledger.store"))
            let identity = SharedMediaNativeScopeIdentity(inventoryID: inventoryID, generation: generation,
                ownerID: ownerID, storeIdentity: store, rootBinding: rootBinding)
            let bytes = try identity.binding
            for (_, url, marker) in markers {
                let written = bytes.withUnsafeBytes { setxattr(url.path, marker, $0.baseAddress, bytes.count, 0, XATTR_CREATE) }
                guard written == 0 else { throw SharedMediaStorageFailure.unavailable }
            }
            let context = ModelContext(container); context.autosaveEnabled = false
            context.insert(SharedMediaInventoryRecord(id: inventoryID, rootIdentity: rootBinding, storeIdentity: store,
                generation: generation, revision: 0, modeRaw: SharedMediaNativeScopedEligibility.mode,
                phaseRaw: SharedMediaNativeScopedEligibility.phase, cursor: ""))
            context.insert(SharedMediaMembershipBootstrapRecord(inventoryID: inventoryID, inventoryGeneration: generation))
            try context.save()
        }
        func owner(drain: SharedMediaNativeOriginalDrain? = nil) throws -> SharedMediaNativeOriginalOwner {
            try .scopedInspection(account: account, drain: drain ?? self.drain)
        }
        func open(_ owner: SharedMediaNativeOriginalOwner, pause: (@Sendable () async -> Void)? = nil) async throws -> SharedMediaNativeScopedSnapshot {
            try await owner.openScoped(container: container, authorityRoot: authority, photoRoot: photo, inboxRoot: inbox,
                inventoryID: inventoryID, pagePause: pause)
        }
        func markerBytes() throws -> [Data?] {
            try markers.map { _, url, name in
                let count = getxattr(url.path, name, nil, 0, 0, 0)
                if count < 0 { guard errno == ENOATTR else { throw SharedMediaStorageFailure.unavailable }; return nil }
                var bytes = Data(count: count)
                let actual = bytes.withUnsafeMutableBytes { getxattr(url.path, name, $0.baseAddress, count, 0, 0) }
                guard actual == count else { throw SharedMediaStorageFailure.conflict }; return bytes
            }
        }
        func ordinaryDraft() throws {
            let context = ModelContext(container); context.autosaveEnabled = false
            let id = UUID()
            context.insert(PhotoPreparationRecord(id: id, ownerID: UUID(), contractVersion: PhotoPreparationPolicy.contract,
                draftID: id, draftGeneration: UUID(), revision: 0, phaseRaw: "draftOwned",
                supportingContextData: Data("ordinary-undecodable-by-native".utf8),
                allocatedByteCount: 0, retirementRequested: false))
            try context.save()
        }
        func terminalReceipts(_ count: Int) throws {
            let context = ModelContext(container); context.autosaveEnabled = false
            for _ in 0..<count {
                let row = SharedMediaAcquisitionReceiptRecord(operationID: UUID(), inventoryID: inventoryID,
                    inventoryGeneration: generation, ownerID: ownerID, requestFingerprint: String(repeating: "a", count: 64),
                    packageID: UUID(), assetID: UUID(), requestData: Data())
                row.phaseRaw = "terminal"; row.terminalOutcomeRaw = "released"; row.revision = 2
                row.packageID = nil; row.assetID = nil; row.requestData = nil
                context.insert(row)
            }
            try context.save()
        }
    }
}
