import Foundation
@testable import Merian
import SwiftData
import Testing

@Suite("Startup-selected native control parent")
@MainActor
struct SharedMediaNativeControlParentTests {
    @Test func freshParentKeepsFenceAndCreationReceiptWithoutGrantingAProfile() throws {
        let h = try Fixture()
        let discovery = try h.discover()
        #expect(discovery.parent.path == h.parent.path)
        #expect(try SharedMediaStorageFileOwner.directoryIdentity(discovery.parent)
            == SharedMediaStorageFileOwner.directoryIdentity(h.parent))
        #expect(discovery.existingProfile == nil)
        #expect(try h.parent.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        let receipt = try h.receipt()
        #expect(receipt.version == 1)
        #expect(receipt.store == (try SharedMediaNativeEligibility.storeIdentity(at: h.store)))
        #expect(receipt.parent == (try SharedMediaStorageFileOwner.directoryIdentity(h.parent)))
        #expect(try FileManager.default.contentsOfDirectory(atPath: h.parent.path) == [SharedMediaNativeBootstrapCodec.parentReceiptName])
        #expect(throws: (any Error).self) { _ = try h.discover() }
        #expect(throws: (any Error).self) { _ = try h.admission.acquireFence(container: h.container) }
        let bytes = try Data(contentsOf: h.receiptURL)
        discovery.invalidate()
        let next = try h.discover()
        #expect(next.existingProfile == nil)
        #expect(try Data(contentsOf: h.receiptURL) == bytes)
        next.invalidate()
    }

    @Test(arguments: SharedMediaNativeParentCreationBoundary.allCases)
    func interruptedCreationNeverAdoptsAnUnprovenDirectory(boundary: SharedMediaNativeParentCreationBoundary) throws {
        let h = try Fixture()
        #expect(throws: (any Error).self) {
            _ = try SharedMediaNativeBootstrapDiscovery.qualificationStartup(container: h.container,
                admission: h.admission, support: h.support, ownerID: h.ownerID,
                fault: { if $0 == boundary { throw Fault.interrupted } })
        }
        #expect(FileManager.default.fileExists(atPath: h.parent.path))
        if boundary == .afterDirectory || boundary == .afterBackupExclusion {
            #expect(!FileManager.default.fileExists(atPath: h.receiptURL.path))
            #expect(throws: (any Error).self) { _ = try h.discover() }
            #expect(!FileManager.default.fileExists(atPath: h.receiptURL.path))
        } else {
            let bytes = try Data(contentsOf: h.receiptURL)
            let recovered = try h.discover()
            #expect(recovered.existingProfile == nil)
            #expect(try Data(contentsOf: h.receiptURL) == bytes)
            recovered.invalidate()
        }
    }

    @Test func fixedParentTransfersToExistingOwnerAndReopensExactInventory() async throws {
        let h = try Fixture(), discovery = try h.discover()
        let id = discovery.inventoryID, bytes = try Data(contentsOf: h.receiptURL)
        let drain = SharedMediaNativeOriginalDrain()
        let owner = try SharedMediaNativeOriginalOwner.appInitialization(account: h.account, drain: drain)
        _ = try await owner.initializeApp(container: h.container, parent: discovery.parent,
            inventoryID: id, discovery: discovery)
        #expect(await drain.shutdown())
        let reopened = try h.discover()
        #expect(reopened.inventoryID == id)
        #expect(reopened.existingProfile?.ownerID == h.ownerID)
        #expect(try Data(contentsOf: h.receiptURL) == bytes)
        reopened.invalidate()
        #expect(throws: (any Error).self) { _ = try h.discover(ownerID: UUID()) }
    }

    @Test(arguments: [SharedMediaNativeBootstrapBoundary.afterIntent, .beforeSave, .afterSave])
    func provenParentPreservesInterruptedBootstrap(boundary: SharedMediaNativeBootstrapBoundary) async throws {
        let h = try Fixture(), discovery = try h.discover()
        let id = discovery.inventoryID, bytes = try Data(contentsOf: h.receiptURL)
        let drain = SharedMediaNativeOriginalDrain()
        let owner = try SharedMediaNativeOriginalOwner.appInitialization(account: h.account, drain: drain)
        await #expect(throws: (any Error).self) {
            _ = try await owner.initializeApp(container: h.container, parent: discovery.parent,
                inventoryID: id, fault: { if $0 == boundary { throw Fault.interrupted } }, discovery: discovery)
        }
        #expect(await drain.shutdown())
        let recovered = try h.discover()
        #expect(recovered.inventoryID == id)
        #expect(try Data(contentsOf: h.receiptURL) == bytes)
        recovered.invalidate()
    }

    @Test(arguments: ["empty", "unexcluded", "foreign", "symlink", "file"])
    func preexistingUnprovenParentIsNeverAdopted(kind: String) throws {
        let h = try Fixture()
        if kind == "file" { try Data("synthetic".utf8).write(to: h.parent) }
        else if kind == "symlink" {
            try FileManager.default.createSymbolicLink(at: h.parent, withDestinationURL: h.support.appendingPathComponent("control"))
        } else {
            try FileManager.default.createDirectory(at: h.parent, withIntermediateDirectories: false)
            if kind != "unexcluded" {
                var url = h.parent, values = URLResourceValues(); values.isExcludedFromBackup = true
                try url.setResourceValues(values)
            }
            if kind == "foreign" { try Data("synthetic".utf8).write(to: h.parent.appendingPathComponent("foreign")) }
        }
        #expect(throws: (any Error).self) { _ = try h.discover() }
        #expect(!FileManager.default.fileExists(atPath: h.receiptURL.path))
        if kind == "file" { #expect(try Data(contentsOf: h.parent) == Data("synthetic".utf8)) }
        if kind == "foreign" { #expect(try Data(contentsOf: h.parent.appendingPathComponent("foreign")) == Data("synthetic".utf8)) }
        if kind == "unexcluded" { #expect(try h.parent.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup != true) }
    }

    @Test(arguments: ["missing", "malformed", "version", "store", "storeParent", "parent", "unexcluded"])
    func changedCreationProofCannotDowngradeToLegacyDiscovery(change: String) throws {
        let h = try Fixture(), discovery = try h.discover()
        discovery.invalidate()
        let original = try h.receipt()
        if change == "missing" { try FileManager.default.removeItem(at: h.receiptURL) }
        else if change == "malformed" { try Data("{}".utf8).write(to: h.receiptURL) }
        else if change == "unexcluded" {
            var url = h.parent, values = URLResourceValues(); values.isExcludedFromBackup = false
            try url.setResourceValues(values)
        } else {
            let receipt = SharedMediaNativeBootstrapCodec.ParentCreation(version: change == "version" ? 2 : 1,
                store: change == "store" ? UUID().uuidString : original.store,
                storeParent: change == "storeParent" ? "0:0" : original.storeParent,
                parent: change == "parent" ? "0:0" : original.parent)
            try SharedMediaNativeBootstrapCodec.encode(receipt).write(to: h.receiptURL)
        }
        let before = try? Data(contentsOf: h.receiptURL)
        #expect(throws: (any Error).self) { _ = try h.discover() }
        #expect((try? Data(contentsOf: h.receiptURL)) == before)
    }

    @Test func associatedDatabaseDoesNotCreateASecondParent() async throws {
        let h = try Fixture(), drain = SharedMediaNativeOriginalDrain()
        let owner = try SharedMediaNativeOriginalOwner.appInitialization(account: h.account, drain: drain)
        _ = try await owner.initializeApp(container: h.container, parent: h.support.appendingPathComponent("control"), inventoryID: UUID())
        #expect(await drain.shutdown())
        #expect(throws: (any Error).self) { _ = try h.discover() }
        #expect(!FileManager.default.fileExists(atPath: h.parent.path))
    }

    @Test func changedReceiptBurnsTheHeldTransferWithoutRepair() async throws {
        let h = try Fixture(), discovery = try h.discover(), drain = SharedMediaNativeOriginalDrain()
        let owner = try SharedMediaNativeOriginalOwner.appInitialization(account: h.account, drain: drain)
        let original = try Data(contentsOf: h.receiptURL)
        try Data("{}".utf8).write(to: h.receiptURL)
        await #expect(throws: (any Error).self) {
            _ = try await owner.initializeApp(container: h.container, parent: discovery.parent,
                inventoryID: discovery.inventoryID, discovery: discovery)
        }
        #expect(try Data(contentsOf: h.receiptURL) == Data("{}".utf8))
        #expect(await drain.shutdown())
        try original.write(to: h.receiptURL)
        let next = try h.discover(); next.invalidate()
    }

    @Test func replacedParentAndWrongContainerCannotUseStartupProvenance() throws {
        let h = try Fixture()
        let other = try ModelContainerFactory.makeInMemoryContainer()
        #expect(throws: (any Error).self) {
            _ = try SharedMediaNativeBootstrapDiscovery.qualificationStartup(container: other,
                admission: h.admission, support: h.support, ownerID: h.ownerID)
        }
        #expect(!FileManager.default.fileExists(atPath: h.parent.path))
        let discovery = try h.discover(); discovery.invalidate()
        let old = h.support.appendingPathComponent("retained-parent")
        try FileManager.default.moveItem(at: h.parent, to: old)
        try FileManager.default.copyItem(at: old, to: h.parent)
        #expect(throws: (any Error).self) { _ = try h.discover() }
        #expect(try Data(contentsOf: h.receiptURL) == Data(contentsOf: old.appendingPathComponent(SharedMediaNativeBootstrapCodec.parentReceiptName)))
    }

    @Test func liveNamespaceIsUnavailableToTestsAndOnlyLifetimeCanDiscover() throws {
        let h = try Fixture()
        #expect(throws: (any Error).self) {
            _ = try SharedMediaNativeBootstrapDiscovery.startup(container: h.container, admission: h.admission, ownerID: h.ownerID)
        }
        #expect(throws: (any Error).self) {
            _ = try SharedMediaNativeBootstrapDiscovery.qualificationStartup(container: h.container,
                admission: h.admission, support: URL.applicationSupportDirectory.resolvingSymlinksInPath().standardizedFileURL, ownerID: h.ownerID)
        }
        let files = try DatabaseActorTestSupport.swiftSources(below: "apps/ios/Merian")
        #expect(files.filter { $0.contents.contains("SharedMediaNativeBootstrapDiscovery.startup(") }.map(\.relativePath)
            == ["Core/Data/SharedMediaStorage/SharedMediaNativeOriginalDrain.swift"])
        #expect(try SharedMediaNativeBootstrapCodec.maximumControlBytes < PhotoPreparationPolicy.metadata)
    }

    private enum Fault: Error { case interrupted }
    @MainActor private struct Fixture {
        let support: URL, container: ModelContainer, admission: NativeReleaseStartupAdmission, ownerID: UUID
        let runtime = AuthRuntimeState()
        var parent: URL { support.appendingPathComponent(SharedMediaNativeBootstrapCodec.parentName) }
        var receiptURL: URL { parent.appendingPathComponent(SharedMediaNativeBootstrapCodec.parentReceiptName) }
        var store: URL { container.configurations.first!.url }
        var account: PhotoOriginalPreparationOwner.AccountAccess { PhotoOriginalPreparationOwner.syntheticAccount(ownerID: ownerID, runtime: runtime) }
        init() throws {
            let existing = try SharedMediaNativeAppBootstrapTests.Store(startupEligible: true)
            support = existing.parent.deletingLastPathComponent(); ownerID = existing.ownerID
            let startup = try existing.startup(); container = startup.0; admission = startup.1
        }
        func discover(ownerID: UUID? = nil) throws -> SharedMediaNativeBootstrapDiscovery {
            try .qualificationStartup(container: container, admission: admission, support: support, ownerID: ownerID ?? self.ownerID)
        }
        func receipt() throws -> SharedMediaNativeBootstrapCodec.ParentCreation {
            try SharedMediaNativeBootstrapCodec.decode(SharedMediaNativeBootstrapCodec.ParentCreation.self, Data(contentsOf: receiptURL))
        }
    }
}
