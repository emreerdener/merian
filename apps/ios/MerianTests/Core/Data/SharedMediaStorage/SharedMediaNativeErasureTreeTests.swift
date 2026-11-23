import Darwin
import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
struct NativeErasureTreeTests {
    typealias Tree = SharedMediaNativeErasureTree
    typealias Manifest = SharedMediaNativeErasureManifest

    @Test func completeTreeRetiresAcrossManifestPagesAndProofRechecksAbsence() throws {
        let fixture = try Fixture(files: 130, receipt: true)
        let tree = try fixture.open()
        try tree.verify()
        let proof = try tree.retire()
        try proof.require(fixture.header, profile: fixture.profile)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.parent.path) == [SharedMediaNativeBootstrapCodec.parentReceiptName])
        try Data([9]).write(to: fixture.parent.appendingPathComponent("unexpected"))
        #expect(throws: (any Error).self) { try proof.require(fixture.header, profile: fixture.profile) }
    }

    @Test(arguments: [0, 1, 2]) func interruptedUnlinkReplaysFromSameManifest(point: Int) throws {
        let fixture = try Fixture(files: 3)
        var didInterrupt = false
        do {
            let tree = try fixture.open()
            #expect(throws: (any Error).self) {
                try tree.retire { boundary in
                    let matches = switch boundary {
                    case .beforeUnlink: point == 0
                    case .afterUnlink: point == 1
                    case .afterParentSync: point == 2
                    }
                    if matches && !didInterrupt { didInterrupt = true; throw SharedMediaStorageFailure.unavailable }
                }
            }
        }
        #expect(didInterrupt)
        let replay = try fixture.open()
        let proof = try replay.retire()
        try proof.require(fixture.header, profile: fixture.profile)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.parent.path).isEmpty)
    }

    @Test(arguments: ["extra", "replacement", "symlink", "hardlink", "parent", "receipt"])
    func changedTreeNeverGrantsAbsence(change: String) throws {
        let fixture = try Fixture(files: 1, receipt: true)
        let tree = try fixture.open()
        switch change {
        case "extra": try Data([2]).write(to: fixture.parent.appendingPathComponent("unexpected"))
        case "replacement": try Data([4, 5]).write(to: fixture.leaves[0], options: .atomic)
        case "symlink":
            try FileManager.default.removeItem(at: fixture.leaves[0])
            try FileManager.default.createSymbolicLink(at: fixture.leaves[0], withDestinationURL: fixture.parent)
        case "hardlink":
            try FileManager.default.linkItem(at: fixture.leaves[0], to: fixture.parent.appendingPathComponent("another-link"))
        case "parent":
            try FileManager.default.moveItem(at: fixture.parent, to: fixture.moved)
            try FileManager.default.createDirectory(at: fixture.parent, withIntermediateDirectories: false)
        default: try Data([7]).write(to: fixture.parent.appendingPathComponent(SharedMediaNativeBootstrapCodec.parentReceiptName))
        }
        #expect(throws: (any Error).self) { try tree.retire() }
        #expect(throws: (any Error).self) { try tree.absence() }
    }

    @Test func unlistedLeafReplacingMissingLeafStillFailsBeforeUnlink() throws {
        let fixture = try Fixture(files: 2)
        try FileManager.default.removeItem(at: fixture.leaves[0])
        try Data([8]).write(to: fixture.leaves[0].deletingLastPathComponent().appendingPathComponent(UUID().uuidString.lowercased()))
        let tree = try fixture.open()
        #expect(throws: (any Error).self) { try tree.retire() }
        #expect(FileManager.default.fileExists(atPath: fixture.leaves[1].path))
    }

    @Test func revokedOuterCheckpointAndIncompleteManifestStopBeforeUnlink() throws {
        let fixture = try Fixture(files: 2)
        var current = true
        do {
            let tree = try fixture.open(checkpoint: { if !current { throw SharedMediaStorageFailure.stale } })
            current = false
            #expect(throws: (any Error).self) { try tree.retire() }
        }
        let tree = try fixture.open(pages: [])
        #expect(throws: (any Error).self) { try tree.retire() }
        #expect(fixture.leaves.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    }

    @Test func failedInitializationReleasesParentLock() throws {
        let fixture = try Fixture(files: 1)
        #expect(throws: (any Error).self) {
            try fixture.open(checkpoint: { throw SharedMediaStorageFailure.stale })
        }
        let tree = try fixture.open()
        try tree.verify()
    }

    @Test func terminalReceiptRequiresClearedRowsAndSurvivesCarrierRemoval() throws {
        let fixture = try Fixture(files: 2, journal: true)
        let container = try #require(fixture.container), tree = try fixture.open()
        let absent = try tree.retire()
        #expect(throws: (any Error).self) { try tree.persistTerminal(container: container) }
        _ = try SharedMediaNativeErasureJournal.complete(container: container, profile: fixture.profile,
            operationID: fixture.header.operationID, checkpoint: {}, absence: absent)
        #expect(throws: (any Error).self) { try tree.persistTerminal(container: container) }
        _ = try SharedMediaNativeErasureJournal.clearSourceRows(container: container, profile: fixture.profile,
            operationID: fixture.header.operationID, checkpoint: {}, absence: absent)
        let proof = try tree.persistTerminal(container: container)
        try SharedMediaNativeErasureJournal.retireCarrier(container: container, profile: fixture.profile,
            header: fixture.header, terminal: proof, checkpoint: {})
        try SharedMediaNativeErasureJournal.requireNoNativeRows(container: container, checkpoint: {})
        try proof.require(fixture.header, profile: fixture.profile)
        try SharedMediaNativeErasureJournal.retireCarrier(container: container, profile: fixture.profile,
            header: fixture.header, terminal: proof, checkpoint: {})
        try Data([8]).write(to: fixture.parent.appendingPathComponent("unexpected"))
        #expect(throws: (any Error).self) { try proof.require(fixture.header, profile: fixture.profile) }
    }

    @Test(arguments: [0, 1, 2, 3]) func interruptedTerminalWriteRetainsClearedJournal(point: Int) throws {
        let fixture = try Fixture(files: 1, journal: true)
        let container = try #require(fixture.container), tree = try fixture.open()
        try fixture.clear(using: tree)
        #expect(throws: (any Error).self) {
            try tree.persistTerminal(container: container) { boundary in
                let index = switch boundary {
                case .beforeWrite: 0
                case .afterWrite: 1
                case .afterSync: 2
                case .beforeReadback: 3
                }
                if index == point { throw SharedMediaStorageFailure.unavailable }
            }
        }
        #expect(try SharedMediaNativeErasureJournal.read(container: container, profile: fixture.profile,
            operationID: fixture.header.operationID, checkpoint: {}).state.stage == .cleared)
        let proof = try tree.persistTerminal(container: container)
        try proof.require(fixture.header, profile: fixture.profile)
    }

    @Test(arguments: SharedMediaNativeErasureJournal.Boundary.allCases)
    func interruptedCarrierRetirementRetainsReceipt(boundary: SharedMediaNativeErasureJournal.Boundary) throws {
        let fixture = try Fixture(files: 1, journal: true)
        let container = try #require(fixture.container), tree = try fixture.open()
        try fixture.clear(using: tree)
        let proof = try tree.persistTerminal(container: container)
        var interrupted = false
        let retire = {
            try SharedMediaNativeErasureJournal.retireCarrier(container: container, profile: fixture.profile,
                header: fixture.header, terminal: proof, checkpoint: {}) { reached in
                    if reached == boundary && !interrupted {
                        interrupted = true; throw SharedMediaStorageFailure.unavailable
                    }
                }
        }
        if boundary == .beforeSave {
            #expect(throws: (any Error).self) { try retire() }
            #expect(try SharedMediaNativeErasureJournal.read(container: container, profile: fixture.profile,
                operationID: fixture.header.operationID, checkpoint: {}).state.stage == .cleared)
        } else { try retire() }
        #expect(interrupted)
        try retire()
        try proof.require(fixture.header, profile: fixture.profile)
        try SharedMediaNativeErasureJournal.requireNoNativeRows(container: container, checkpoint: {})
    }

    @Test(arguments: ["malformed", "sameOperation", "foreignStore", "previousOperation"])
    func terminalReceiptReplacementRequiresExactParentAndStore(change: String) throws {
        let fixture = try Fixture(files: 1, journal: true)
        let container = try #require(fixture.container), tree = try fixture.open()
        try fixture.clear(using: tree)
        let changes: [String: Any] = change == "sameOperation" ? ["controlSHA256": String(repeating: "e", count: 64)]
            : change == "foreignStore" ? ["operationID": UUID().uuidString, "storeFileIdentity": "9:9"]
            : ["operationID": UUID().uuidString]
        let header: SharedMediaNativeErasureHeader = try SharedMediaNativeReceivingTestFixture.copy(fixture.header, changes: changes)
        let receipt = SharedMediaNativeErasureTerminalReceipt(version: 1, profile: fixture.profile, header: header)
        let bytes = try change == "malformed" ? Data([1]) : receipt.encoded()
        try fixture.writeTerminal(bytes)
        if change == "previousOperation" {
            let proof = try tree.persistTerminal(container: container)
            try proof.require(fixture.header, profile: fixture.profile)
        } else {
            #expect(throws: (any Error).self) { try tree.persistTerminal(container: container) }
        }
    }

    @Test func changedTerminalReceiptCannotRetireCarrier() throws {
        let fixture = try Fixture(files: 1, journal: true)
        let container = try #require(fixture.container), tree = try fixture.open()
        try fixture.clear(using: tree)
        let proof = try tree.persistTerminal(container: container)
        try fixture.writeTerminal(Data([1]))
        #expect(throws: (any Error).self) {
            try SharedMediaNativeErasureJournal.retireCarrier(container: container, profile: fixture.profile,
                header: fixture.header, terminal: proof, checkpoint: {})
        }
        #expect(try SharedMediaNativeErasureJournal.read(container: container, profile: fixture.profile,
            operationID: fixture.header.operationID, checkpoint: {}).state.stage == .cleared)
    }

    @Test func coldTerminalRecoveryRequiresExactReceiptEmptyTreeAndZeroRows() throws {
        let fixture = try Fixture(files: 1, journal: true)
        let container = try #require(fixture.container)
        do {
            let tree = try fixture.open()
            try fixture.clear(using: tree)
            let proof = try tree.persistTerminal(container: container)
            try SharedMediaNativeErasureJournal.retireCarrier(container: container, profile: fixture.profile,
                header: fixture.header, terminal: proof, checkpoint: {})
        }
        let expected = SharedMediaNativeErasureTerminalReceipt(version: 1, profile: fixture.profile, header: fixture.header)
        func recover(_ receipt: SharedMediaNativeErasureTerminalReceipt) throws -> SharedMediaNativeErasureTerminal {
            try Tree.recoverTerminal(container: container, parent: fixture.parent, held: .qualificationErasureParent(fixture.parent),
                expected: receipt, checkpoint: {})
        }
        do {
            let proof = try recover(expected)
            try proof.require(fixture.header, profile: fixture.profile)
        }
        for changes: [String: Any] in [["operationID": UUID().uuidString], ["operation": "accountDeletion"]] {
            let changed: SharedMediaNativeErasureHeader = try SharedMediaNativeReceivingTestFixture.copy(fixture.header, changes: changes)
            #expect(throws: (any Error).self) {
                try recover(.init(version: 1, profile: fixture.profile, header: changed))
            }
        }
        let context = ModelContext(container); context.autosaveEnabled = false
        let row = SharedMediaMembershipBootstrapRecord(inventoryID: UUID(), inventoryGeneration: UUID())
        context.insert(row); try context.save()
        #expect(throws: (any Error).self) { try recover(expected) }
        context.delete(row); try context.save()
        try Data([7]).write(to: fixture.parent.appendingPathComponent("unexpected"))
        #expect(throws: (any Error).self) { try recover(expected) }
    }

    @MainActor private final class Fixture {
        let parent: URL
        let moved: URL
        let profile: SharedMediaNativeAppProfile
        let header: SharedMediaNativeErasureHeader
        let pages: [Data]
        let leaves: [URL]
        let container: ModelContainer?

        init(files: Int, receipt: Bool = false, journal: Bool = false) throws {
            parent = URL.applicationSupportDirectory.resolvingSymlinksInPath().standardizedFileURL
                .appendingPathComponent("erasure-tree-" + UUID().uuidString.lowercased())
            moved = parent.appendingPathExtension("moved")
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            var excluded = URLResourceValues(); excluded.isExcludedFromBackup = true
            var parentURL = parent; try parentURL.setResourceValues(excluded)
            profile = .init(ownerID: UUID(), inventoryID: UUID(), generation: UUID(), storeIdentity: UUID().uuidString,
                physicalBinding: String(repeating: "a", count: 64), receiptDigest: String(repeating: "b", count: 64),
                physicalBindingFormat: .physicalRootsV1)
            let receiptBytes = Data([1, 2, 3])
            if receipt { try receiptBytes.write(to: parent.appendingPathComponent(SharedMediaNativeBootstrapCodec.parentReceiptName)) }
            let root = parent.appendingPathComponent("capture")
            let child = root.appendingPathComponent(SharedMediaCaptureRootJournal.childName)
            try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
            var entries: [Manifest.Entry] = [
                .init(namespace: .capture, token: ".", kind: .directory, identity: try Self.identity(root)),
                .init(namespace: .capture, token: SharedMediaCaptureRootJournal.childName, kind: .directory, identity: try Self.identity(child))
            ]
            var created: [URL] = []
            for _ in 0..<files {
                let name = UUID().uuidString.lowercased(), url = child.appendingPathComponent(name)
                try Data([1, 3, 5]).write(to: url); created.append(url)
                entries.append(.init(namespace: .capture, token: SharedMediaCaptureRootJournal.childName + "/" + name,
                    kind: .file, identity: try Self.identity(url, file: true)))
            }
            leaves = created
            entries.sort { $0.key < $1.key }
            let operation = UUID(), profileHash = try SharedMediaAcquisitionEncoding.digest(profile.binding)
            var encoded: [Data] = []
            for start in stride(from: 0, to: entries.count, by: Manifest.pageSize) {
                encoded.append(try Manifest.Page(version: 1, operationID: operation, profileSHA256: profileHash,
                    ordinal: Int64(encoded.count), previousSHA256: encoded.last.map(SharedMediaAcquisitionEncoding.digest),
                    entries: Array(entries[start..<min(start + Manifest.pageSize, entries.count)])).encoded(profile: profile))
            }
            pages = encoded
            var tables = SharedMediaNativeErasureGraph.modelTypes.map {
                SharedMediaNativeErasureGraph.Table(name: String(describing: $0), rows: Int64(files), sha256: String(repeating: "c", count: 64))
            }
            if journal {
                let schema = Schema(SharedMediaNativeErasureGraph.modelTypes + SharedMediaNativeErasureGraph.carrierModelTypes + [SharedMediaInventoryRecord.self])
                let store = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
                let context = ModelContext(store); context.autosaveEnabled = false
                context.insert(SharedMediaInventoryRecord(id: profile.inventoryID, rootIdentity: try profile.rootIdentity,
                    storeIdentity: profile.storeIdentity, generation: profile.generation, revision: 0,
                    modeRaw: SharedMediaNativeAppProfile.mode, phaseRaw: SharedMediaNativeAppProfile.phase, cursor: ""))
                try context.save()
                tables = try SharedMediaNativeErasureGraph.snapshot(context, checkpoint: {})
                container = store
            } else { container = nil }
            header = .init(version: 1, operation: .signOut, operationID: operation, profileSHA256: profileHash,
                storeFileIdentity: "1:2", storeParentIdentity: "1:3", controlParentIdentity: try Self.identity(parent),
                parentReceiptSHA256: receipt ? SharedMediaAcquisitionEncoding.digest(receiptBytes) : nil,
                controlSHA256: String(repeating: "d", count: 64), sourceRevision: 0, sourceTables: tables,
                pageCount: Int64(encoded.count), entryCount: Int64(entries.count), lastPageSHA256: SharedMediaAcquisitionEncoding.digest(encoded.last!))
            if let container {
                _ = try SharedMediaNativeErasureJournal.begin(header, container: container, profile: profile, checkpoint: {})
                for bytes in pages {
                    _ = try SharedMediaNativeErasureJournal.append(bytes, container: container, profile: profile,
                        operationID: header.operationID, checkpoint: {})
                }
                _ = try SharedMediaNativeErasureJournal.retire(container: container, profile: profile,
                    operationID: header.operationID, checkpoint: {})
            }
        }

        deinit {
            try? FileManager.default.removeItem(at: parent)
            try? FileManager.default.removeItem(at: moved)
        }

        func open(checkpoint: @escaping () throws -> Void = {}, pages override: [Data]? = nil) throws -> Tree {
            let data = override ?? pages
            return try Tree(parent: parent, held: .qualificationErasureParent(parent), profile: profile,
                header: header, checkpoint: checkpoint, pages: { [self] removing, body in
                    if let container {
                        try SharedMediaNativeErasureJournal.visitManifest(container: container, profile: profile,
                            header: header, removing: removing, checkpoint: checkpoint, body: body)
                    } else { for bytes in data { try body(bytes) } }
                })
        }

        func clear(using tree: Tree) throws {
            let container = try #require(container), absent = try tree.retire()
            _ = try SharedMediaNativeErasureJournal.complete(container: container, profile: profile,
                operationID: header.operationID, checkpoint: {}, absence: absent)
            _ = try SharedMediaNativeErasureJournal.clearSourceRows(container: container, profile: profile,
                operationID: header.operationID, checkpoint: {}, absence: absent)
        }

        func writeTerminal(_ bytes: Data) throws {
            let fd = Darwin.open(parent.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard fd >= 0 else { throw SharedMediaStorageFailure.unavailable }
            defer { Darwin.close(fd) }
            guard bytes.withUnsafeBytes({ fsetxattr(fd, SharedMediaNativeErasureTerminalReceipt.marker,
                $0.baseAddress, $0.count, 0, 0) }) == 0 else { throw SharedMediaStorageFailure.unavailable }
        }

        private static func identity(_ url: URL, file: Bool = false) throws -> String {
            var value = stat()
            guard lstat(url.path, &value) == 0 else { throw SharedMediaStorageFailure.unavailable }
            let root = "\(value.st_dev):\(value.st_ino)"
            return file ? "\(root):\(value.st_size):\(value.st_mtimespec.tv_sec):\(value.st_mtimespec.tv_nsec):\(value.st_ctimespec.tv_sec):\(value.st_ctimespec.tv_nsec)" : root
        }
    }
}
