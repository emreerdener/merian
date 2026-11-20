import Darwin
import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Native fixture store admission", .serialized)
@MainActor
struct SharedMediaNativeStorageRepositoryTests {
    enum Fault: Error, Equatable { case injected }

    @Test(arguments: ["reserved", "completed", "terminal", "unknown"])
    func acquisitionReceiptsRemainLiabilitiesAcrossColdReopen(_ phase: String) throws {
        let base = Self.root(), inventoryID = UUID(), operationID = UUID()
        let generation = UUID(), ownerID = UUID(), packageID = UUID(), assetID = UUID()
        let request = Data("synthetic-request".utf8), result = Data("synthetic-result".utf8)
        let fingerprint = String(repeating: "a", count: 64)
        do {
            let h = try Harness(base: base, inventoryID: inventoryID)
            let context = ModelContext(h.container); context.autosaveEnabled = false
            let row = SharedMediaAcquisitionReceiptRecord(operationID: operationID,
                inventoryID: inventoryID, inventoryGeneration: generation, ownerID: ownerID,
                requestFingerprint: fingerprint, packageID: packageID, assetID: assetID, requestData: request)
            row.phaseRaw = phase
            if phase == "completed" { row.resultData = result; row.revision = 1 }
            if phase == "terminal" {
                row.packageID = nil; row.assetID = nil; row.requestData = nil
                row.terminalOutcomeRaw = "released"; row.revision = 2
            }
            context.insert(row); try context.save()
        }
        let h = try Harness(base: base, inventoryID: inventoryID)
        let context = ModelContext(h.container)
        #expect(try SharedMediaStorageRepository.hasLiabilities(in: context))
        #expect(throws: (any Error).self) { try h.native() }
        #expect(throws: (any Error).self) { try h.legacy() }
        let fresh = ModelContext(h.container)
        let row = try #require(fresh.fetch(FetchDescriptor<SharedMediaAcquisitionReceiptRecord>()).first)
        #expect(row.id == operationID && row.schemaVersion == 1 && row.phaseRaw == phase)
        #expect(row.inventoryID == inventoryID && row.inventoryGeneration == generation && row.ownerID == ownerID)
        #expect(row.requestFingerprint == fingerprint)
        #expect(row.packageID == (phase == "terminal" ? nil : packageID))
        #expect(row.assetID == (phase == "terminal" ? nil : assetID))
        #expect(row.requestData == (phase == "terminal" ? nil : request))
        #expect(row.resultData == (phase == "completed" ? result : nil))
        #expect(row.terminalOutcomeRaw == (phase == "terminal" ? "released" : nil))
        #expect(row.revision == (phase == "terminal" ? 2 : phase == "completed" ? 1 : 0))
        #expect(try fresh.fetchCount(FetchDescriptor<SharedMediaAcquisitionReceiptRecord>()) == 1)
        #expect(try fresh.fetchCount(FetchDescriptor<SharedMediaInventoryRecord>()) == 0)
    }

    @Test func nativeBindingAndBootstrapSurviveColdContainerReopen() throws {
        let base = Self.root(), id = UUID()
        let saved: SharedMediaStorageSnapshot
        do {
            let h = try Harness(base: base, inventoryID: id), owner = try h.native()
            saved = try owner.snapshot()
            #expect(saved.phase == "readyNativeAccountingV1" && saved.revision == 0)
            let context = ModelContext(h.container)
            #expect(try context.fetchCount(FetchDescriptor<SharedMediaMembershipBootstrapRecord>()) == 1)
            #expect(try context.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first?.modeRaw == "nativeQualificationV1")
            #expect(throws: (any Error).self) { try h.native() }
        }
        let reopened = try Harness(base: base, inventoryID: id)
        #expect(try reopened.native().snapshot() == saved)
    }

    @Test(arguments: [SharedMediaNativeInitializationBoundary.afterPhotoBinding, .afterInboxBinding,
                      .afterAuthorityBinding, .beforeSave, .afterSave])
    func interruptedInitializationNeverRepairsOrAdopts(_ boundary: SharedMediaNativeInitializationBoundary) throws {
        let h = try Harness()
        #expect(throws: Fault.injected) { try h.native { if $0 == boundary { throw Fault.injected } } }
        let context = ModelContext(h.container)
        let count = boundary == .afterSave ? 1 : 0
        #expect(try context.fetchCount(FetchDescriptor<SharedMediaInventoryRecord>()) == count)
        #expect(try context.fetchCount(FetchDescriptor<SharedMediaMembershipBootstrapRecord>()) == count)
        if boundary == .afterSave {
            #expect(try h.native().snapshot().revision == 0)
        } else {
            #expect(throws: (any Error).self) { try h.native() }
            #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<SharedMediaInventoryRecord>()) == 0)
        }
    }

    @Test(arguments: ["missingBootstrap", "generation", "contract", "revision", "mode", "phase", "foreignGraph",
                      "rootBinding", "storeIdentity", "inventoryID", "bootstrapID", "bootstrapRevision", "cursor"])
    func invalidReopenPreservesTheSavedGraph(_ change: String) throws {
        let h = try Harness()
        do { let owner = try h.native(); _ = try owner.snapshot() }
        let context = ModelContext(h.container); context.autosaveEnabled = false
        let inventory = try #require(context.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first)
        let receipt = try #require(context.fetch(FetchDescriptor<SharedMediaMembershipBootstrapRecord>()).first)
        switch change {
        case "missingBootstrap": context.delete(receipt)
        case "generation": receipt.inventoryGeneration = UUID()
        case "contract": receipt.contractVersion = 2
        case "revision": inventory.revision = 1
        case "mode": inventory.modeRaw = "p1InboxQualification"
        case "phase": inventory.phaseRaw = "readyP1"
        case "rootBinding": inventory.rootIdentity = "wrong"
        case "storeIdentity": inventory.storeIdentity = UUID().uuidString
        case "inventoryID": inventory.id = UUID()
        case "bootstrapID": receipt.id = UUID()
        case "bootstrapRevision": receipt.revision = 1
        case "cursor": inventory.cursor = "unexpected"
        case "foreignGraph": context.insert(SharedMediaLeaseRecord(id: UUID(), allocationID: UUID(), processEpoch: UUID(), purposeRaw: "unknown", stateRaw: "unknown"))
        default: Issue.record("Unknown corruption")
        }
        try context.save()
        #expect(throws: (any Error).self) { try h.native() }
        let fresh = ModelContext(h.container)
        #expect(try fresh.fetchCount(FetchDescriptor<SharedMediaInventoryRecord>()) == 1)
        #expect(try fresh.fetchCount(FetchDescriptor<SharedMediaMembershipBootstrapRecord>()) == (change == "missingBootstrap" ? 0 : 1))
        #expect(try fresh.fetchCount(FetchDescriptor<SharedMediaLeaseRecord>()) == (change == "foreignGraph" ? 1 : 0))
    }

    @Test func legacyAndNativeConstructorsCannotCrossOpen() throws {
        let native = try Harness()
        do { let owner = try native.native(); _ = try owner.snapshot() }
        #expect(throws: (any Error).self) { try native.legacy() }
        #expect(try native.native().snapshot().revision == 0)
        let legacy = try Harness()
        do { let owner = try legacy.legacy(); _ = try owner.snapshot() }
        #expect(throws: (any Error).self) { try legacy.native() }
        #expect(try legacy.legacy().snapshot().phase == "readyP1")
    }

    @Test(arguments: ["photo", "inbox"], [false, true])
    func coldReopenRejectsMissingOrSymlinkNamespaceWithoutCreatingIt(_ namespace: String, symlink: Bool) throws {
        let h = try Harness()
        do { let owner = try h.native(); _ = try owner.snapshot() }
        let target = h.namespace(namespace)
        try FileManager.default.removeItem(at: target)
        if symlink { try FileManager.default.createSymbolicLink(at: target, withDestinationURL: h.other) }
        #expect(throws: (any Error).self) { try h.native() }
        if symlink {
            #expect(try FileManager.default.destinationOfSymbolicLink(atPath: target.path) == h.other.path)
        } else { #expect(!FileManager.default.fileExists(atPath: target.path)) }
    }

    @Test(arguments: ["photo", "inbox", "authority"])
    func heldOwnerRejectsReplacedDirectory(_ kind: String) throws {
        let h = try Harness(), owner = try h.native()
        let target = kind == "authority" ? h.authority : h.namespace(kind)
        try FileManager.default.moveItem(at: target, to: h.base.appendingPathComponent("moved"))
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        #expect(throws: (any Error).self) { try owner.snapshot() }
    }

    @Test(arguments: ["photo", "inbox"])
    func legacySharedReopenDoesNotRecreateMissingNamespace(_ namespace: String) throws {
        let h = try Harness()
        do { let owner = try h.legacy(); _ = try owner.snapshot() }
        let target = h.namespace(namespace)
        try FileManager.default.removeItem(at: target)
        #expect(throws: (any Error).self) { try h.legacy() }
        #expect(!FileManager.default.fileExists(atPath: target.path))
    }

    @Test func sharedPhotoOnlyReopenRejectsMissingNamespaceWhileStandaloneStillCreates() throws {
        let h = try Harness()
        do {
            let owner = try SharedMediaStorageRepository(container: h.container, authorityRoot: h.authority,
                inventoryID: h.inventoryID, mode: .p1Qualification, sources: [SharedMediaPhotoLedger.namespace: h.photo])
            _ = try owner.snapshot()
        }
        let target = h.namespace("photo")
        try FileManager.default.removeItem(at: target)
        #expect(throws: (any Error).self) {
            try SharedMediaStorageRepository(container: h.container, authorityRoot: h.authority,
                inventoryID: h.inventoryID, mode: .p1Qualification, sources: [SharedMediaPhotoLedger.namespace: h.photo])
        }
        #expect(!FileManager.default.fileExists(atPath: target.path))
        do { let standalone = try PhotoPreparationLockedFiles(root: h.other); try standalone.checkIdentity() }
        let standaloneNamespace = h.other.appendingPathComponent("PhotoPreparation")
        try FileManager.default.removeItem(at: standaloneNamespace)
        let reopened = try PhotoPreparationLockedFiles(root: h.other)
        try reopened.checkIdentity()
        #expect(FileManager.default.fileExists(atPath: standaloneNamespace.path))
    }

    @Test(arguments: [URL.documentsDirectory, URL.applicationSupportDirectory], [false, true])
    func rejectsInstalledStorageLocationsBeforeCreatingBindings(_ parent: URL, resolved: Bool) throws {
        let location = resolved ? parent.resolvingSymlinksInPath() : parent
        let h = try Harness(base: location.appendingPathComponent("native-rejected-" + UUID().uuidString))
        #expect(throws: SharedMediaStorageFailure.invalid) { try h.native() }
        #expect(try FileManager.default.contentsOfDirectory(atPath: h.authority.path).isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: h.photo.path).isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: h.inbox.path).isEmpty)
        #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<SharedMediaInventoryRecord>()) == 0)
        #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<SharedMediaMembershipBootstrapRecord>()) == 0)
        for (root, name) in [(h.authority, "com.merian.shared-media-store-v1"),
                             (h.photo, "com.merian.p1-shared-v1"), (h.inbox, SharedMediaInboxFiles.marker)] {
            let size = getxattr(root.path, name, nil, 0, 0, 0), error = errno
            #expect(size == -1 && error == ENOATTR)
        }
    }

    nonisolated private static func root() -> URL {
        FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("native-owner-" + UUID().uuidString)
    }

    @MainActor private struct Harness {
        let base: URL, authority: URL, photo: URL, inbox: URL, other: URL
        let inventoryID: UUID, container: ModelContainer
        init(base: URL = SharedMediaNativeStorageRepositoryTests.root(), inventoryID: UUID = UUID()) throws {
            self.base = base; self.inventoryID = inventoryID
            authority = base.appendingPathComponent("authority"); photo = base.appendingPathComponent("photo")
            inbox = base.appendingPathComponent("inbox"); other = base.appendingPathComponent("other")
            let database = base.appendingPathComponent("database")
            for root in [authority, photo, inbox, other, database] {
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            }
            let schema = Schema(versionedSchema: CurrentSchema.self)
            container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema,
                url: database.appendingPathComponent("ledger.store"), cloudKitDatabase: .none)])
        }
        func native() throws -> SharedMediaNativeStorageRepository {
            try .qualification(container: container, authorityRoot: authority, photoRoot: photo, inboxRoot: inbox, inventoryID: inventoryID)
        }
        func native(fault: @escaping (SharedMediaNativeInitializationBoundary) throws -> Void) throws -> SharedMediaNativeStorageRepository {
            try .qualification(container: container, authorityRoot: authority, photoRoot: photo, inboxRoot: inbox, inventoryID: inventoryID, fault: fault)
        }
        func legacy() throws -> SharedMediaStorageRepository {
            try .init(container: container, authorityRoot: authority, inventoryID: inventoryID, mode: .p1InboxQualification,
                sources: [SharedMediaPhotoLedger.namespace: photo, SharedMediaInboxFiles.namespace: inbox])
        }
        func namespace(_ kind: String) -> URL {
            kind == "photo" ? photo.appendingPathComponent("PhotoPreparation") : inbox.appendingPathComponent("InboxSources")
        }
    }
}
