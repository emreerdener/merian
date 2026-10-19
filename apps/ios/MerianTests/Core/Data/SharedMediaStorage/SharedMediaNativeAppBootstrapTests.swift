import Darwin
import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Native app profile bootstrap", .serialized)
@MainActor
struct SharedMediaNativeAppBootstrapTests {
    private enum Interruption: Error { case injected }

    @Test func exactReopenRetainsIdentityAndDoesNotEnableDispatch() async throws {
        let h = try Store(), owner = try h.owner()
        let ordinary = ModelContext(h.container); ordinary.autosaveEnabled = false
        let id = UUID()
        ordinary.insert(PhotoPreparationRecord(id: id, ownerID: UUID(), contractVersion: PhotoPreparationPolicy.contract,
            draftID: id, draftGeneration: UUID(), revision: 0, phaseRaw: "draftOwned",
            supportingContextData: Data("ordinary-draft".utf8), allocatedByteCount: 0, retirementRequested: false))
        try ordinary.save()
        let initial = try await h.open(owner), bytes = try h.controls()
        #expect(initial.phase == SharedMediaNativeAppProfile.phase)
        #expect(try await owner.appInitializationSnapshot() == initial)
        await #expect(throws: (any Error).self) { _ = try await owner.snapshot() }
        await #expect(throws: (any Error).self) { _ = try await owner.prepareOriginal(packageID: UUID(), draftGeneration: UUID(), ordinal: 0, kind: .picker) }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let next = try h.owner(); #expect(try await h.open(next) == initial)
        #expect(try h.controls() == bytes)
        #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<PhotoPreparationRecord>()) == 1)
        #expect(await next.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: SharedMediaNativeBootstrapBoundary.allCases)
    func interruptionRecoversOnlyExactIntentAndFinal(_ boundary: SharedMediaNativeBootstrapBoundary) async throws {
        let h = try Store(), owner = try h.owner()
        await #expect(throws: Interruption.self) {
            _ = try await h.open(owner, fault: { if $0 == boundary { throw Interruption.injected } })
        }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let intent = try Data(contentsOf: h.parent.appendingPathComponent(SharedMediaNativeBootstrapCodec.intentName))
        let decoded = try SharedMediaNativeBootstrapCodec.decode(SharedMediaNativeBootstrapCodec.Intent.self, intent)
        let next = try h.owner(), result = try await h.open(next)
        #expect(result.generation == decoded.generation)
        #expect(try Data(contentsOf: h.parent.appendingPathComponent(SharedMediaNativeBootstrapCodec.intentName)) == intent)
        #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<SharedMediaInventoryRecord>()) == 1)
        #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<SharedMediaMembershipBootstrapRecord>()) == 1)
        #expect(await next.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: SharedMediaNativeBootstrapCodec.names)
    func finalReceiptNeverRecreatesReplacedDirectory(_ name: String) async throws {
        let h = try Store(), first = try h.owner()
        await #expect(throws: Interruption.self) {
            _ = try await h.open(first, fault: { if $0 == .afterFinal { throw Interruption.injected } })
        }
        #expect(await first.invalidateAndAwaitForAccountTransition())
        let url = h.parent.appendingPathComponent(name), moved = url.appendingPathExtension("retained")
        try FileManager.default.moveItem(at: url, to: moved)
        let before = try h.controls(), next = try h.owner()
        await #expect(throws: (any Error).self) { _ = try await h.open(next) }
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(try h.controls() == before)
        #expect(await next.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: SharedMediaNativeBootstrapCodec.names)
    func preFinalRecordedDirectoryCannotBeSubstituted(_ name: String) async throws {
        let h = try Store(), first = try h.owner()
        let index = try #require(SharedMediaNativeBootstrapCodec.names.firstIndex(of: name))
        let boundary: SharedMediaNativeBootstrapBoundary = [.afterAuthorityRoot, .afterPhotoRoot, .afterPhotoNamespace, .afterInboxRoot, .afterInboxNamespace][index]
        await #expect(throws: Interruption.self) { _ = try await h.open(first, fault: { if $0 == boundary { throw Interruption.injected } }) }
        #expect(await first.invalidateAndAwaitForAccountTransition())
        let url = h.parent.appendingPathComponent(name)
        // Move outside the control parent so rejection must use descriptor
        // identity, rather than merely detecting an unexpected sibling name.
        try FileManager.default.moveItem(at: url, to: h.parent.deletingLastPathComponent().appendingPathComponent("replaced"))
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        let before = try h.controls(), next = try h.owner()
        await #expect(throws: (any Error).self) { _ = try await h.open(next) }
        #expect(try h.controls() == before)
        #expect(await next.invalidateAndAwaitForAccountTransition())
    }

    @Test func missingProgressAndChangedParentAreHeld() async throws {
        for change in ["missing", "parent", "receipt", "malformed"] {
            let h = try Store(), first = try h.owner()
            await #expect(throws: Interruption.self) { _ = try await h.open(first, fault: { if $0 == .afterPhotoNamespace { throw Interruption.injected } }) }
            #expect(await first.invalidateAndAwaitForAccountTransition())
            if change == "missing" {
                try FileManager.default.removeItem(at: h.parent.appendingPathComponent(SharedMediaNativeBootstrapCodec.progressNames[2]))
            } else if change == "malformed" {
                // A torn progress write is evidence to hold, not permission to
                // overwrite it or proceed with the not-yet-created inbox.
                try Data("{\"version\":".utf8).write(to: h.parent.appendingPathComponent(SharedMediaNativeBootstrapCodec.progressNames[2]))
            } else if change == "receipt" {
                let url = h.parent.appendingPathComponent(SharedMediaNativeBootstrapCodec.progressNames[2])
                let old = try SharedMediaNativeBootstrapCodec.decode(SharedMediaNativeBootstrapCodec.Progress.self, Data(contentsOf: url))
                let bad = SharedMediaNativeBootstrapCodec.Progress(version: old.version, intentDigest: old.intentDigest,
                    name: old.name, identity: old.identity, parentIdentity: "1:1")
                try SharedMediaNativeBootstrapCodec.encode(bad).write(to: url)
            } else {
                let url = h.parent.appendingPathComponent("photo"), moved = h.parent.deletingLastPathComponent().appendingPathComponent("replaced")
                try FileManager.default.moveItem(at: url, to: moved)
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
                try FileManager.default.moveItem(at: moved.appendingPathComponent("PhotoPreparation"), to: url.appendingPathComponent("PhotoPreparation"))
            }
            let before = try h.controls(), next = try h.owner()
            await #expect(throws: (any Error).self) { _ = try await h.open(next) }
            #expect(try h.controls() == before)
            #expect(!FileManager.default.fileExists(atPath: h.parent.appendingPathComponent("inbox").path))
            #expect(await next.invalidateAndAwaitForAccountTransition())
        }
    }

    @Test(arguments: ["intent", "final", "partialDatabase", "missingMarker", "changedOwner", "changedInventory", "extraFile", "symlink"])
    func conflictingEvidenceIsHeldWithoutRepair(_ change: String) async throws {
        let h = try Store(), first = try h.owner(); _ = try await h.open(first)
        #expect(await first.invalidateAndAwaitForAccountTransition())
        if change == "intent" || change == "final" {
            let name = change == "intent" ? SharedMediaNativeBootstrapCodec.intentName : SharedMediaNativeBootstrapCodec.finalName
            try Data("{}".utf8).write(to: h.parent.appendingPathComponent(name))
        } else if change == "partialDatabase" {
            let context = ModelContext(h.container); context.autosaveEnabled = false
            context.delete(try #require(try context.fetch(FetchDescriptor<SharedMediaMembershipBootstrapRecord>()).first)); try context.save()
        } else if change == "missingMarker" {
            #expect(removexattr(h.parent.appendingPathComponent("photo").path, "com.merian.p1-shared-v1", 0) == 0)
        } else if change == "extraFile" {
            try Data([1]).write(to: h.parent.appendingPathComponent("photo/PhotoPreparation/unexpected"))
        } else if change == "symlink" {
            let original = h.parent.appendingPathComponent("inbox/InboxSources")
            let moved = original.appendingPathExtension("retained")
            try FileManager.default.moveItem(at: original, to: moved)
            try FileManager.default.createSymbolicLink(at: original, withDestinationURL: moved)
        }
        let before = try h.controls(), next = try h.owner(ownerID: change == "changedOwner" ? UUID() : nil)
        await #expect(throws: (any Error).self) { _ = try await h.open(next, inventoryID: change == "changedInventory" ? UUID() : nil) }
        #expect(try h.controls() == before)
        if change == "missingMarker" { #expect(getxattr(h.parent.appendingPathComponent("photo").path, "com.merian.p1-shared-v1", nil, 0, 0, 0) < 0) }
        #expect(await next.invalidateAndAwaitForAccountTransition())
    }

    @Test func unknownEmptyRootsAreNotAdoptedAndLowSpacePreservesEmptyState() async throws {
        for existing in [false, true] {
            let h = try Store()
            if existing { try FileManager.default.createDirectory(at: h.parent.appendingPathComponent("authority"), withIntermediateDirectories: false) }
            let before = try FileManager.default.contentsOfDirectory(atPath: h.parent.path), owner = try h.owner()
            await #expect(throws: (any Error).self) {
                _ = try await h.open(owner, availableBytes: existing ? nil : PhotoPreparationPolicy.minimumFree)
            }
            #expect(try FileManager.default.contentsOfDirectory(atPath: h.parent.path) == before)
            #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<SharedMediaInventoryRecord>()) == 0)
            #expect(await owner.invalidateAndAwaitForAccountTransition())
        }
    }

    @Test func competingOwnerCannotReleaseOrReplaceRetainedFences() async throws {
        let h = try Store(), first = try h.owner(); let expected = try await h.open(first), before = try h.controls()
        let other = try h.owner()
        await #expect(throws: (any Error).self) { _ = try await h.open(other) }
        #expect(try h.controls() == before)
        #expect(try await first.appInitializationSnapshot() == expected)
        #expect(await other.invalidateAndAwaitForAccountTransition())
        #expect(await first.invalidateAndAwaitForAccountTransition())
        let next = try h.owner(); #expect(try await h.open(next) == expected)
        #expect(await next.invalidateAndAwaitForAccountTransition())
    }

    @Test func controlEncodingFitsExistingBoundsWithoutPackageCharge() throws {
        #expect(try SharedMediaNativeBootstrapCodec.maximumControlBytes < PhotoPreparationPolicy.metadata)
        let profile = SharedMediaNativeAppProfile(ownerID: UUID(), inventoryID: UUID(), generation: UUID(),
            storeIdentity: UUID().uuidString, physicalBinding: String(repeating: "f", count: 64), receiptDigest: String(repeating: "f", count: 64))
        #expect(try profile.binding.count <= 512)
        #expect(PhotoPreparationPolicy.package == 96 * PhotoPreparationPolicy.mib)
        #expect(PhotoPreparationPolicy.durable == 384 * PhotoPreparationPolicy.mib)
    }

    @MainActor private struct Store {
        let parent: URL, container: ModelContainer
        let ownerID = UUID(), inventoryID = UUID(), runtime = AuthRuntimeState()
        init() throws {
            let base = URL.applicationSupportDirectory.resolvingSymlinksInPath().appendingPathComponent("native-bootstrap-" + UUID().uuidString)
            parent = base.appendingPathComponent("control")
            let database = base.appendingPathComponent("database")
            for directory in [parent, database] {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                var url = directory, values = URLResourceValues(); values.isExcludedFromBackup = true; try url.setResourceValues(values)
            }
            let schema = Schema(versionedSchema: CurrentSchema.self)
            container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema,
                url: database.appendingPathComponent("ledger.store"), cloudKitDatabase: .none)])
        }
        func owner(ownerID: UUID? = nil) throws -> SharedMediaNativeOriginalOwner {
            try .appInitialization(account: PhotoOriginalPreparationOwner.syntheticAccount(ownerID: ownerID ?? self.ownerID, runtime: runtime), drain: .init())
        }
        func open(_ owner: SharedMediaNativeOriginalOwner, inventoryID: UUID? = nil,
                  fault: ((SharedMediaNativeBootstrapBoundary) throws -> Void)? = nil,
                  availableBytes: Int64? = nil) async throws -> SharedMediaStorageSnapshot {
            try await owner.initializeApp(container: container, parent: parent, inventoryID: inventoryID ?? self.inventoryID,
                fault: fault, availableBytes: availableBytes)
        }
        func controls() throws -> [String: Data] {
            var result: [String: Data] = [:]
            for name in [SharedMediaNativeBootstrapCodec.intentName, SharedMediaNativeBootstrapCodec.finalName] + SharedMediaNativeBootstrapCodec.progressNames {
                let url = parent.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: url.path) { result[name] = try Data(contentsOf: url) }
            }
            for (name, marker) in [("authority", "com.merian.shared-media-store-v1"), ("photo", "com.merian.p1-shared-v1"), ("inbox", SharedMediaInboxFiles.marker)] {
                let url = parent.appendingPathComponent(name)
                let count = getxattr(url.path, marker, nil, 0, 0, 0)
                if count >= 0 {
                    var bytes = Data(count: count)
                    guard bytes.withUnsafeMutableBytes({ getxattr(url.path, marker, $0.baseAddress, count, 0, 0) }) == count else { throw SharedMediaStorageFailure.unavailable }
                    result[marker] = bytes
                }
            }
            return result
        }
    }
}
