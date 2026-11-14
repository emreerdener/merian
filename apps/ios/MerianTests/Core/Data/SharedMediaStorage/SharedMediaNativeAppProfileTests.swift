import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Versioned native physical-root profile", .serialized)
@MainActor
struct SharedMediaNativeAppProfileTests {
    private typealias Profile = SharedMediaNativeAppProfile
    private typealias Codec = SharedMediaNativeBootstrapCodec
    private typealias Store = SharedMediaNativeAppBootstrapTests.Store
    private enum Interruption: Error { case injected }
    private final class Resources: NSObject {}

    @Test func headerSnapshotsObserveSuccessiveCommitsAndDeletion() throws {
        let fixture = try HeaderFixture(), first = try fixture.snapshot()
        #expect(first.inventory.revision == 0 && first.bootstrapRevision == 0)
        let context = fixture.context()
        let inventory = try #require(try context.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first)
        let bootstrap = try #require(try context.fetch(FetchDescriptor<SharedMediaMembershipBootstrapRecord>()).first)
        inventory.revision = 7; bootstrap.revision = 11; try context.save()
        let second = try fixture.snapshot()
        #expect(second.inventory.revision == 7 && second.bootstrapRevision == 11)
        #expect(second != first && first.inventory.revision == 0 && first.bootstrapRevision == 0)
        context.delete(bootstrap); try context.save()
        #expect(throws: SharedMediaStorageFailure.conflict) { _ = try fixture.snapshot() }
        #expect(throws: SharedMediaStorageFailure.conflict) {
            _ = try SharedMediaNativeAppEligibility.header(context: fixture.context(), scope: fixture.scope)
        }
    }

    @Test(arguments: ["inventoryMissing", "bootstrapMissing", "profile", "mode", "phase", "cursor",
        "inventoryRevision", "bootstrapRevision", "contract", "generation", "store", "owner", "root", "dirty"])
    func bothHeaderProjectionsRejectInvalidAuthority(_ fault: String) throws {
        let fixture = try HeaderFixture(); _ = try fixture.snapshot()
        let context = fixture.context()
        let inventory = try #require(try context.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first)
        let bootstrap = try #require(try context.fetch(FetchDescriptor<SharedMediaMembershipBootstrapRecord>()).first)
        switch fault {
        case "inventoryMissing": context.delete(inventory)
        case "bootstrapMissing": context.delete(bootstrap)
        case "profile": inventory.rootIdentity = "malformed"
        case "mode": inventory.modeRaw = "unknown"
        case "phase": inventory.phaseRaw = "unknown"
        case "cursor": inventory.cursor = "unexpected"
        case "inventoryRevision": inventory.revision = -1
        case "bootstrapRevision": bootstrap.revision = -1
        case "contract": bootstrap.contractVersion = 1
        case "generation": bootstrap.inventoryGeneration = UUID()
        case "store": inventory.storeIdentity = UUID().uuidString
        case "dirty": inventory.revision += 1
        default: break
        }
        if fault != "dirty" { try context.save() }
        let scope = SharedMediaNativeScopeIdentity(inventoryID: fixture.scope.inventoryID, generation: fixture.scope.generation,
            ownerID: fault == "owner" ? UUID() : fixture.scope.ownerID, storeIdentity: fixture.scope.storeIdentity,
            rootBinding: fault == "root" ? "wrong-root" : fixture.scope.rootBinding)
        #expect(throws: (any Error).self) {
            _ = try SharedMediaNativeAppEligibility.snapshot(context: context, scope: scope)
        }
        #expect(throws: (any Error).self) {
            _ = try SharedMediaNativeAppEligibility.header(context: context, scope: scope)
        }
        context.rollback()
    }

    @MainActor private struct HeaderFixture {
        let container: ModelContainer
        let scope: SharedMediaNativeScopeIdentity
        init() throws {
            let schema = Schema([SharedMediaInventoryRecord.self, SharedMediaMembershipBootstrapRecord.self])
            container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
            let profile = Profile(ownerID: UUID(), inventoryID: UUID(), generation: UUID(), storeIdentity: UUID().uuidString,
                physicalBinding: String(repeating: "a", count: 64), receiptDigest: String(repeating: "b", count: 64))
            scope = try .init(inventoryID: profile.inventoryID, generation: profile.generation, ownerID: profile.ownerID,
                storeIdentity: profile.storeIdentity, rootBinding: profile.rootIdentity)
            let context = ModelContext(container); context.autosaveEnabled = false
            context.insert(SharedMediaInventoryRecord(id: profile.inventoryID, rootIdentity: scope.rootBinding,
                storeIdentity: profile.storeIdentity, generation: profile.generation, revision: 0,
                modeRaw: Profile.mode, phaseRaw: Profile.phase, cursor: ""))
            let bootstrap = SharedMediaMembershipBootstrapRecord(inventoryID: profile.inventoryID, inventoryGeneration: profile.generation)
            bootstrap.contractVersion = 2; context.insert(bootstrap); try context.save()
        }
        func context() -> ModelContext {
            let context = ModelContext(container); context.autosaveEnabled = false; return context
        }
        func snapshot() throws -> SharedMediaNativeAppEligibility.Header {
            try SharedMediaNativeAppEligibility.snapshot(context: context(), scope: scope)
        }
    }

    @Test func legacyCompleteSnapshotsRetainBothCanonicalEncodings() throws {
        // Captured from the synthetic no-save07 fixture before adding a format
        // field. These are committed legacy bytes, not values built by new code.
        let url = try #require(Bundle(for: Resources.self).url(forResource: "NativeProfileLegacySnapshots", withExtension: "json"))
        let golden = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))
        func bytes(_ key: String) throws -> Data {
            let encoded = try #require(golden[key])
            return try #require(Data(base64Encoded: encoded))
        }
        let preparedBytes = try bytes("prepared"), receivedBytes = try bytes("received"), releaseBytes = try bytes("release")
        let prepared = try SharedMediaNativeReceivingIntent.Prepared.decode(preparedBytes)
        let received = try SharedMediaNativeReceivingIntent.Received.decode(receivedBytes, prepared: prepared)
        let release = try SharedMediaNativeReleaseStartRequest.decode(releaseBytes)
        try release.requireMatch(prepared: prepared, received: received)
        #expect(prepared.profile.physicalBindingFormat == .absolutePathsV1)
        #expect(try prepared.encoded() == preparedBytes)
        #expect(try received.encoded(prepared: prepared) == receivedBytes)
        #expect(try release.encoded() == releaseBytes)
        try checkBootstrapEncoding(prepared, golden: preparedBytes)
        try checkBootstrapEncoding(received, golden: receivedBytes)
        try checkBootstrapEncoding(release, golden: releaseBytes)
        #expect(try Codec.decode([String].self, prepared.profile.binding).count == 7)
    }

    private func checkBootstrapEncoding<T: Codable>(_ value: T, golden: Data) throws {
        // These synthetic outer snapshots contain base64 payloads; slash escape
        // removal is the sole difference between the two existing encoders.
        let expected = Data(String(decoding: golden, as: UTF8.self).replacingOccurrences(of: "\\/", with: "/").utf8)
        #expect(try Codec.encode(value) == expected)
        #expect(try Codec.encode(Codec.decode(T.self, expected)) == expected)
    }

    @Test func explicitFormatRoundTripsAndRejectsNoncanonicalAlternatives() throws {
        for format in [Profile.PhysicalBindingFormat.absolutePathsV1, .physicalRootsV1] {
            let profile = Profile(ownerID: UUID(), inventoryID: UUID(), generation: UUID(),
                storeIdentity: UUID().uuidString, physicalBinding: String(repeating: "a", count: 64),
                receiptDigest: String(repeating: "b", count: 64), physicalBindingFormat: format)
            let bytes = try Codec.encode(profile), fields = try Codec.decode([String].self, profile.binding)
            #expect(try Codec.decode(Profile.self, bytes) == profile)
            #expect(try Profile.PhysicalBindingFormat(bindingFields: fields) == format)
            #expect(fields.count == (format == .absolutePathsV1 ? 7 : 8))
            #expect(try profile.binding.count <= 512)
            let row = SharedMediaInventoryRecord(id: profile.inventoryID,
                rootIdentity: try profile.rootIdentity, storeIdentity: profile.storeIdentity,
                generation: profile.generation, revision: 0, modeRaw: Profile.mode, phaseRaw: Profile.phase, cursor: "")
            #expect(try SharedMediaNativeAppEligibility.profile(row) == profile)
            for tag: Any in [NSNull(), "absolutePathsV1", "physicalRootsV9", 3] {
                var object = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
                object["physicalBindingFormat"] = tag
                let bad = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
                #expect(throws: (any Error).self) { _ = try Codec.decode(Profile.self, bad) }
            }
            row.rootIdentity = String(decoding: try Codec.encode(Array(fields.prefix(7)) + ["absolutePathsV1"]), as: UTF8.self)
            #expect(throws: (any Error).self) { _ = try SharedMediaNativeAppEligibility.profile(row) }
            let duplicate = Data((String(decoding: bytes.dropLast(), as: UTF8.self) + ",\"physicalBindingFormat\":\"physicalRootsV1\",\"physicalBindingFormat\":\"physicalRootsV1\"}").utf8)
            #expect(throws: (any Error).self) { _ = try Codec.decode(Profile.self, duplicate) }
        }
        #expect(throws: (any Error).self) { _ = try Profile.PhysicalBindingFormat(journalVersion: 4) }
    }

    @Test(arguments: [2, 3])
    func journalVersionKeepsExactCommitmentAcrossReopenAndRename(_ version: Int) async throws {
        let h = try Store()
        try await seedIntent(h, version: version)
        let first = try h.owner(), initial = try await h.open(first)
        #expect(await first.invalidateAndAwaitForAccountTransition())
        let context = ModelContext(h.container); context.autosaveEnabled = false
        let row = try #require(try context.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first)
        let profile = try SharedMediaNativeAppEligibility.profile(row)
        #expect(profile.physicalBindingFormat == (version == 2 ? .absolutePathsV1 : .physicalRootsV1))
        let controls = try h.controls(), same = try h.dispatchOwner()
        #expect(try await same.openApp(container: h.container, parent: h.parent, inventoryID: h.inventoryID).inventory == initial)
        #expect(await same.invalidateAndAwaitForAccountTransition())
        #expect(try h.controls() == controls)
        let moved = h.parent.appendingPathExtension("relocated")
        try FileManager.default.moveItem(at: h.parent, to: moved)
        let next = try h.dispatchOwner()
        if version == 3 {
            #expect(try await next.openApp(container: h.container, parent: moved, inventoryID: h.inventoryID).inventory == initial)
        } else {
            await #expect(throws: SharedMediaStorageFailure.conflict) {
                _ = try await next.openApp(container: h.container, parent: moved, inventoryID: h.inventoryID)
            }
        }
        #expect(await next.invalidateAndAwaitForAccountTransition())
        #expect(try h.controls(at: moved) == controls)
        #expect(try SharedMediaNativeAppEligibility.profile(row) == profile)
    }

    @Test func incompleteLegacyIntentRemainsLegacyAfterRelocation() async throws {
        let h = try Store(); try await seedIntent(h, version: 2)
        let before = try h.controls(), moved = h.parent.appendingPathExtension("relocated")
        try FileManager.default.moveItem(at: h.parent, to: moved)
        let owner = try h.owner()
        _ = try await owner.initializeApp(container: h.container, parent: moved, inventoryID: h.inventoryID)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let after = try h.controls(at: moved)
        #expect(after[Codec.intentName] == before[Codec.intentName])
        let row = try #require(try ModelContext(h.container).fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first)
        #expect(try SharedMediaNativeAppEligibility.profile(row).physicalBindingFormat == .absolutePathsV1)
        let final = try Codec.decode(Codec.Final.self, #require(after[Codec.finalName]))
        #expect(final.version == 2)
    }

    @Test(arguments: SharedMediaNativeBootstrapBoundary.allCases.filter { $0 != .afterIntent })
    func legacyProgressAndPartialMarkersResumeWithoutRewriting(_ boundary: SharedMediaNativeBootstrapBoundary) async throws {
        let h = try Store(); try await seedIntent(h, version: 2)
        let interrupted = try h.owner()
        await #expect(throws: Interruption.self) {
            _ = try await h.open(interrupted, fault: { if $0 == boundary { throw Interruption.injected } })
        }
        #expect(await interrupted.invalidateAndAwaitForAccountTransition())
        let retained = try h.controls(), resumed = try h.owner()
        _ = try await h.open(resumed)
        #expect(await resumed.invalidateAndAwaitForAccountTransition())
        let completed = try h.controls()
        for (name, bytes) in retained { #expect(completed[name] == bytes) }
        let final = try Codec.decode(Codec.Final.self, #require(completed[Codec.finalName]))
        #expect(final.version == 2)
        for name in Codec.progressNames {
            #expect(try Codec.decode(Codec.Progress.self, #require(completed[name])).version == 2)
        }
        let row = try #require(try ModelContext(h.container).fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first)
        #expect(try SharedMediaNativeAppEligibility.profile(row).physicalBindingFormat == .absolutePathsV1)
    }

    @Test func directoryTraversalPreservesLexicalAndSymlinkRejection() throws {
        let remote = try #require(URL(string: "https://example.invalid/directory"))
        #expect(throws: SharedMediaStorageFailure.invalid) { _ = try SharedMediaStorageFileOwner.directoryIdentity(remote) }
        let traversal = try #require(URL(string: "file:///merian-lexical/../directory"))
        #expect(traversal.pathComponents.contains(".."))
        #expect(throws: SharedMediaStorageFailure.invalid) { _ = try SharedMediaStorageFileOwner.directoryIdentity(traversal) }
        let base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("directory-traversal-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let real = base.appendingPathComponent("real", isDirectory: true)
        let child = real.appendingPathComponent("child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        let identity = try SharedMediaStorageFileOwner.directoryIdentity(child)
        #expect(try SharedMediaStorageFileOwner.directoryIdentity(child) == identity)
        let link = base.appendingPathComponent("link", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        for url in [link, link.appendingPathComponent("child", isDirectory: true)] {
            #expect(throws: SharedMediaStorageFailure.unavailable) { _ = try SharedMediaStorageFileOwner.directoryIdentity(url) }
        }
        try FileManager.default.moveItem(at: real, to: base.appendingPathComponent("held", isDirectory: true))
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        #expect(try SharedMediaStorageFileOwner.directoryIdentity(child) != identity)
    }

    @Test func physicalDigestDistinguishesCopiesNamespacesAndSymlinks() throws {
        let base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("profile-binding-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let original = base.appendingPathComponent("original", isDirectory: true)
        for name in ["authority", "photo", "inbox"] {
            try FileManager.default.createDirectory(at: original.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        func digest(_ root: URL, _ format: Profile.PhysicalBindingFormat = .physicalRootsV1) throws -> String {
            try Profile.rootBinding(format: format,
                authority: SharedMediaStorageFileOwner.directoryIdentity(root.appendingPathComponent("authority", isDirectory: true)),
                sources: [SharedMediaPhotoLedger.namespace: root.appendingPathComponent("photo", isDirectory: true),
                    SharedMediaInboxFiles.namespace: root.appendingPathComponent("inbox", isDirectory: true)])
        }
        let physical = try digest(original), legacy = try digest(original, .absolutePathsV1)
        let moved = base.appendingPathComponent("moved", isDirectory: true)
        try FileManager.default.moveItem(at: original, to: moved)
        #expect(try digest(moved) == physical)
        #expect(try digest(moved, .absolutePathsV1) != legacy)
        let copied = base.appendingPathComponent("copied", isDirectory: true)
        try FileManager.default.copyItem(at: moved, to: copied)
        #expect(try digest(copied) != physical)
        let photo = moved.appendingPathComponent("photo", isDirectory: true)
        let inbox = moved.appendingPathComponent("inbox", isDirectory: true)
        let authority = try SharedMediaStorageFileOwner.directoryIdentity(moved.appendingPathComponent("authority", isDirectory: true))
        #expect(try Profile.rootBinding(format: .physicalRootsV1, authority: authority,
            sources: [SharedMediaPhotoLedger.namespace: inbox, SharedMediaInboxFiles.namespace: photo]) != physical)
        #expect(throws: (any Error).self) {
            _ = try Profile.rootBinding(format: .physicalRootsV1, authority: authority,
                sources: [SharedMediaPhotoLedger.namespace: photo, "unknown": inbox])
        }
        #expect(throws: (any Error).self) {
            _ = try Profile.rootBinding(format: .physicalRootsV1, authority: authority,
                sources: [SharedMediaPhotoLedger.namespace: photo, SharedMediaInboxFiles.namespace: photo])
        }
        let held = moved.appendingPathComponent("held", isDirectory: true)
        try FileManager.default.moveItem(at: photo, to: held)
        try FileManager.default.createSymbolicLink(at: photo, withDestinationURL: held)
        #expect(throws: (any Error).self) { _ = try digest(moved) }
        try FileManager.default.removeItem(at: photo)
        try FileManager.default.createDirectory(at: photo, withIntermediateDirectories: false)
        #expect(try digest(moved) != physical)
    }

    @Test(arguments: [2, 3], ["progress", "final"])
    func crossVersionJournalRecordsNeverRepairOrAdopt(_ version: Int, _ change: String) async throws {
        let h = try Store(); try await seedIntent(h, version: version)
        let first = try h.owner(); _ = try await h.open(first)
        #expect(await first.invalidateAndAwaitForAccountTransition())
        let name = change == "progress" ? Codec.progressNames[0] : Codec.finalName
        let url = h.parent.appendingPathComponent(name)
        var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        object["version"] = version == 2 ? 3 : 2
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]).write(to: url)
        let before = try h.controls(), owner = try h.dispatchOwner()
        await #expect(throws: (any Error).self) { _ = try await owner.openApp(container: h.container, parent: h.parent, inventoryID: h.inventoryID) }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        #expect(try h.controls() == before)
    }

    private func seedIntent(_ h: Store, version: Int) async throws {
        let owner = try h.owner()
        await #expect(throws: Interruption.self) { _ = try await h.open(owner, fault: { if $0 == .afterIntent { throw Interruption.injected } }) }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let url = h.parent.appendingPathComponent(Codec.intentName)
        let current = try Codec.decode(Codec.Intent.self, Data(contentsOf: url))
        #expect(current.version == 3)
        if version == 2 {
            // Seed a historical pre-profile intent only. Production never
            // converts a journal, marker, profile or accepted operation.
            let old = Codec.Intent(version: 2, ownerID: current.ownerID, inventoryID: current.inventoryID,
                generation: current.generation, operationID: current.operationID, nonce: current.nonce,
                store: current.store, parent: current.parent, storeParent: current.storeParent, names: current.names)
            try Codec.encode(old).write(to: url)
        }
    }
}
