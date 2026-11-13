import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite("Reanalysis input library presence", .sharedProcessState(.offlineQueueManager))
struct ReanalysisInputInventoryTests {
    private typealias Receipt = ObservationReanalysisInputReceipt
    private typealias Ledger = ObservationReanalysisInputLedger
    private typealias Persistence = ObservationReanalysisInputPersistence

    @MainActor private final class Fixture {
        let root: URL
        let container: ModelContainer
        let defaults: UserDefaults
        let suite = "reanalysis-input-inventory-" + UUID().uuidString
        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let schema = Schema(CurrentSchema.models)
            container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
            defaults = try #require(UserDefaults(suiteName: suite))
        }
        func remove() {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        func baseline() throws -> Ledger {
            func identity(_ inode: UInt64) -> Receipt.Identity { .init(device: 1, inode: inode, birthSeconds: 100, birthNanoseconds: 0) }
            let value = try Ledger(namespaceGeneration: UUID(), documents: identity(1), namespace: identity(2),
                directories: (3...6).map { identity(UInt64($0)) })
            try Persistence.initialize(value, container: container, validate: { _ in })
            return value
        }
        func inventory() throws -> LibraryMutationInventory {
            try LibraryMutationInventory.read(from: container, userDefaults: defaults)
        }
        func empty() throws -> Bool {
            try LibraryMutationInventory.isEmptyLibrary(in: container, userDefaults: defaults, inputDocuments: root)
        }
    }

    @Test func quiescentControlIsNotPendingWorkButStillRequiresOutgoingPurge() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        #expect(try fixture.empty())
        let ledger = try fixture.baseline()
        #expect(try fixture.inventory().pendingJobs == 0)
        #expect(try fixture.inventory().isReady)
        #expect(!(try fixture.empty()))
        #expect(try LibraryMutationInventory.hasInputOwnership(in: fixture.container, documents: fixture.root))
        let receipt = try Receipt(ownerID: UUID(), parentID: UUID(), childID: UUID(), planDigest: String(repeating: "a", count: 64),
            documents: ledger.documents, namespace: ledger.namespace, namespaceGeneration: ledger.namespaceGeneration,
            slot: 0, useGeneration: UUID(), directory: ledger.slots[0].directory)
        _ = try Persistence.reserve(receipt, container: fixture.container, validate: { _ in })
        #expect(try fixture.inventory().pendingJobs == 2)
        #expect(!(try fixture.inventory().isReady))
        let retiring = try receipt.retiring(), completed = try retiring.completed()
        _ = try Persistence.advance(from: receipt, to: retiring, container: fixture.container, validate: {})
        _ = try Persistence.advance(from: retiring, to: completed, container: fixture.container, validate: {})
        #expect(try fixture.inventory().isReady)
        #expect(!(try fixture.empty()))
        let context = ModelContext(fixture.container)
        context.insert(OfflineJobRecord(id: "unrelated-pending", kind: .future)); try context.save()
        #expect(try fixture.inventory().pendingJobs == 1)
        #expect(!(try fixture.inventory().isReady))
    }

    @Test(arguments: ["invalidControl", "missingControlWithCompletedReceipt"])
    func malformedInputOwnershipCannotBeExcludedAsQuiescent(fault: String) throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        _ = try fixture.baseline()
        let context = ModelContext(fixture.container)
        let control = try #require(try context.fetchOfflineJob(id: Ledger.jobID))
        if fault == "invalidControl" { control.metadataJSON = "invalid" }
        else {
            context.delete(control)
            context.insert(OfflineJobRecord(id: Receipt.prefix + UUID().uuidString.lowercased(), kind: .observationReanalysisErasure,
                status: .complete, metadataJSON: "unrecognized completed ownership"))
        }
        try context.save()
        #expect(throws: (any Error).self) { _ = try fixture.inventory() }
        #expect(try LibraryMutationInventory.hasInputOwnership(in: fixture.container, documents: fixture.root))
    }

    @Test(arguments: ["directory", "regularFile", "danglingSymlink"])
    func anyPhysicalNamespacePreventsEmptyLibraryClassification(kind: String) throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let path = fixture.root.appendingPathComponent("ReanalysisInputs")
        switch kind {
        case "directory": try FileManager.default.createDirectory(at: path, withIntermediateDirectories: false)
        case "regularFile": try Data([1]).write(to: path)
        default: try FileManager.default.createSymbolicLink(at: path, withDestinationURL: fixture.root.appendingPathComponent("missing"))
        }
        #expect(try fixture.inventory().isReady)
        #expect(!(try fixture.empty()))
        #expect(try LibraryMutationInventory.hasInputOwnership(in: fixture.container, documents: fixture.root))
    }

    @Test(arguments: ["missing", "notDirectory", "symlink"])
    func rootLookupFailureNeverBecomesAbsence(kind: String) throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let path = fixture.root.appendingPathComponent("unreadable-root")
        if kind == "notDirectory" { try Data([1]).write(to: path) }
        if kind == "symlink" { try FileManager.default.createSymbolicLink(at: path, withDestinationURL: fixture.root) }
        #expect(throws: (any Error).self) {
            _ = try LibraryMutationInventory.hasInputOwnership(in: fixture.container, documents: path)
        }
    }
}
