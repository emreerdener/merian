import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
struct NativeErasureJournalTests {
    typealias Journal = SharedMediaNativeErasureJournal
    typealias Manifest = SharedMediaNativeErasureManifest

    @Test func physicalManifestReaderRequiresRetirementAndFencesTerminalPhases() throws {
        let fixture = try Fixture()
        func visit(removing: Bool) throws -> Int {
            var count = 0
            try Journal.visitManifest(container: fixture.container, profile: fixture.profile, header: fixture.header,
                removing: removing, checkpoint: {}, body: { _ in count += 1 })
            return count
        }
        _ = try fixture.begin(); _ = try fixture.append(0); _ = try fixture.append(1)
        #expect(throws: (any Error).self) { try visit(removing: false) }
        #expect(throws: (any Error).self) { try visit(removing: true) }
        _ = try fixture.retire()
        #expect(try visit(removing: true) == 2)
        _ = try fixture.complete()
        #expect(try visit(removing: false) == 2)
        #expect(throws: (any Error).self) { try visit(removing: true) }
        _ = try fixture.clear()
        #expect(try visit(removing: false) == 2)
        #expect(throws: (any Error).self) { try visit(removing: true) }
    }

    @Test func incompletePagesKeepAdmissionClosedAndReplayExactly() throws {
        let fixture = try Fixture()
        let begun = try fixture.begin()
        #expect(begun.state.stage == .preparing && begun.pages == 0)
        #expect(throws: (any Error).self) { try fixture.retire() }
        let first = try fixture.append(0)
        #expect(first.pages == 1 && !first.hasCompleteManifest)
        #expect(try fixture.append(0) == first)
        #expect(throws: (any Error).self) { try fixture.retire() }
        let complete = try fixture.append(1)
        #expect(complete.hasCompleteManifest)
        let retiring = try fixture.retire()
        #expect(retiring.state.stage == .retiring)
        #expect(try fixture.retire() == retiring)
        #expect(throws: (any Error).self) { try fixture.append(1) }
        let context = ModelContext(fixture.container)
        let inventory = try #require(try context.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first)
        #expect(throws: (any Error).self) { try SharedMediaNativeAppEligibility.profile(inventory) }
        #expect(try SharedMediaNativeAppEligibility.profileAssertion(inventory) == fixture.profile)
    }

    @Test func interruptedHeaderAndPageSavesResumeOnlyExactCommittedBytes() throws {
        for boundary in Journal.Boundary.allCases {
            let fixture = try Fixture()
            var injected = false
            let fault: (Journal.Boundary) throws -> Void = {
                if !injected, $0 == boundary { injected = true; throw SharedMediaStorageFailure.unavailable }
            }
            if boundary == .beforeSave {
                #expect(throws: (any Error).self) { try fixture.begin(boundary: fault) }
                #expect(try ModelContext(fixture.container).fetchCount(FetchDescriptor<SharedMediaNativeErasurePageRecord>()) == 0)
                _ = try fixture.begin()
            } else {
                #expect(try fixture.begin(boundary: fault).pages == 0)
            }
            injected = false
            if boundary == .beforeSave {
                #expect(throws: (any Error).self) { try fixture.append(0, boundary: fault) }
                #expect(try fixture.read().pages == 0)
            } else {
                #expect(try fixture.append(0, boundary: fault).pages == 1)
            }
            _ = try fixture.append(0)
            _ = try fixture.append(1)
            #expect(try fixture.retire().state.id == fixture.header.operationID)
        }
    }

    @Test(arguments: ["owner", "operation", "ordinal", "kind", "body", "header", "extra", "source"])
    func replacedOrUnknownEvidenceBlocksRetirement(change: String) throws {
        let fixture = try Fixture()
        _ = try fixture.begin(); _ = try fixture.append(0); _ = try fixture.append(1)
        let context = ModelContext(fixture.container); context.autosaveEnabled = false
        let row = try #require(try context.fetch(FetchDescriptor<SharedMediaNativeErasurePageRecord>(
            predicate: #Predicate { $0.kindRaw == "page" && $0.ordinal == 0 })).first)
        switch change {
        case "owner": row.ownerID = UUID()
        case "operation": row.operationID = UUID()
        case "ordinal": row.ordinal = 4
        case "kind": row.kindRaw = "future"
        case "body": row.bodyData.append(0x20)
        case "header":
            let header = try #require(try context.fetch(FetchDescriptor<SharedMediaNativeErasurePageRecord>(
                predicate: #Predicate { $0.kindRaw == "header" })).first)
            header.bodySHA256 = String(repeating: "d", count: 64)
        case "extra":
            context.insert(SharedMediaNativeErasurePageRecord(operationID: UUID(), inventoryID: fixture.profile.inventoryID,
                inventoryGeneration: fixture.profile.generation, ownerID: fixture.profile.ownerID,
                profileSHA256: fixture.header.profileSHA256, kindRaw: "future", ordinal: 0,
                bodyData: Data(), bodySHA256: String(repeating: "d", count: 64)))
        default:
            context.insert(SharedMediaMembershipBootstrapRecord(inventoryID: fixture.profile.inventoryID,
                inventoryGeneration: fixture.profile.generation))
        }
        try context.save()
        #expect(throws: (any Error).self) { try fixture.retire() }
        let inventory = try #require(try ModelContext(fixture.container).fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first)
        #expect(try SharedMediaNativeLibraryErasureState.read(inventory).stage == .preparing)
    }

    @Test func gapForeignOperationAndRevokedScopeCannotAppend() throws {
        let fixture = try Fixture(); _ = try fixture.begin()
        #expect(throws: (any Error).self) { try fixture.append(1) }
        #expect(throws: (any Error).self) {
            try Journal.append(fixture.pages[0], container: fixture.container, profile: fixture.profile,
                operationID: UUID(), checkpoint: {})
        }
        #expect(throws: (any Error).self) {
            try Journal.append(fixture.pages[0], container: fixture.container, profile: fixture.profile,
                operationID: fixture.header.operationID, checkpoint: { throw SharedMediaStorageFailure.closed })
        }
        #expect(try fixture.read().pages == 0)
    }

    @Test func absenceIsRequiredBeforeCompletionAndAtomicRowClear() throws {
        let fixture = try Fixture(hasSourceRows: true)
        _ = try fixture.begin(); _ = try fixture.append(0); _ = try fixture.append(1)
        #expect(throws: (any Error).self) { try fixture.complete() }
        #expect(throws: (any Error).self) { try fixture.clear() }
        _ = try fixture.retire()
        #expect(throws: (any Error).self) {
            try fixture.complete(absence: { _ in throw SharedMediaStorageFailure.conflict })
        }
        #expect(try fixture.read().state.stage == .retiring)
        _ = try fixture.complete()
        #expect(throws: (any Error).self) {
            try fixture.clear(absence: { _ in throw SharedMediaStorageFailure.conflict })
        }
        #expect(try ModelContext(fixture.container).fetchCount(FetchDescriptor<SharedMediaMembershipBootstrapRecord>()) == 1)
        let cleared = try fixture.clear()
        #expect(cleared.state.stage == .cleared && cleared.hasCompleteManifest)
        #expect(try fixture.clear() == cleared)
        let context = ModelContext(fixture.container)
        #expect(try SharedMediaNativeErasureGraph.snapshot(context, checkpoint: {}).allSatisfy { $0.rows == 0 })
        #expect(try context.fetchCount(FetchDescriptor<SharedMediaNativeErasurePageRecord>()) == 3)
        #expect(try context.fetchCount(FetchDescriptor<SharedMediaInventoryRecord>()) == 1)
        #expect(throws: (any Error).self) {
            try fixture.clear(absence: { _ in throw SharedMediaStorageFailure.conflict })
        }
    }

    @Test(arguments: [false, true], Journal.Boundary.allCases)
    func interruptedCompletionAndClearNeverLoseTheRecoveryJournal(clearing: Bool, boundary: Journal.Boundary) throws {
        let fixture = try Fixture(hasSourceRows: true, onDisk: true)
        _ = try fixture.begin(); _ = try fixture.append(0); _ = try fixture.append(1); _ = try fixture.retire()
        if clearing { _ = try fixture.complete() }
        var injected = false
        let fault: (Journal.Boundary) throws -> Void = {
            if !injected, $0 == boundary { injected = true; throw SharedMediaStorageFailure.unavailable }
        }
        let perform = { try clearing ? fixture.clear(boundary: fault) : fixture.complete(boundary: fault) }
        if boundary == .beforeSave {
            #expect(throws: (any Error).self) { try perform() }
            #expect(try fixture.read().state.stage == (clearing ? .complete : .retiring))
            #expect(try ModelContext(fixture.container).fetchCount(FetchDescriptor<SharedMediaMembershipBootstrapRecord>()) == 1)
        } else {
            #expect(try perform().state.stage == (clearing ? .cleared : .complete))
        }
        _ = try clearing ? fixture.clear() : fixture.complete()
        #expect(try ModelContext(fixture.container).fetchCount(FetchDescriptor<SharedMediaNativeErasurePageRecord>()) == 3)
    }

    @Test(arguments: [false, true]) func sourceDeletionCrossesPagesInOneCommit(onDisk: Bool) throws {
        let fixture = try Fixture(sourceRows: SharedMediaStoragePolicy.pageSize + 3, onDisk: onDisk)
        _ = try fixture.begin(); _ = try fixture.append(0); _ = try fixture.append(1); _ = try fixture.retire()
        _ = try fixture.complete(); _ = try fixture.clear()
        #expect(try ModelContext(fixture.container).fetchCount(FetchDescriptor<SharedMediaMembershipBootstrapRecord>()) == 0)
    }

    @MainActor private final class Fixture {
        private let directoryURL: URL?
        let container: ModelContainer
        let profile: SharedMediaNativeAppProfile
        let header: SharedMediaNativeErasureHeader
        let pages: [Data]

        init(hasSourceRows: Bool = false, sourceRows: Int = 0, onDisk: Bool = false) throws {
            let schema = Schema(SharedMediaNativeErasureGraph.modelTypes + SharedMediaNativeErasureGraph.carrierModelTypes + [SharedMediaInventoryRecord.self])
            if onDisk {
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent("native-erasure-journal-" + UUID().uuidString)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                directoryURL = directory
                container = try ModelContainer(for: schema,
                    configurations: [ModelConfiguration(schema: schema, url: directory.appendingPathComponent("store.sqlite"))])
            } else {
                directoryURL = nil
                container = try ModelContainer(for: schema,
                    configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
            }
            profile = .init(ownerID: UUID(), inventoryID: UUID(), generation: UUID(), storeIdentity: UUID().uuidString,
                physicalBinding: String(repeating: "a", count: 64), receiptDigest: String(repeating: "b", count: 64),
                physicalBindingFormat: .physicalRootsV1)
            let context = ModelContext(container); context.autosaveEnabled = false
            context.insert(SharedMediaInventoryRecord(id: profile.inventoryID, rootIdentity: try profile.rootIdentity,
                storeIdentity: profile.storeIdentity, generation: profile.generation, revision: 7,
                modeRaw: SharedMediaNativeAppProfile.mode, phaseRaw: SharedMediaNativeAppProfile.phase, cursor: ""))
            for _ in 0..<max(sourceRows, hasSourceRows ? 1 : 0) {
                context.insert(SharedMediaMembershipBootstrapRecord(inventoryID: UUID(),
                    inventoryGeneration: profile.generation))
            }
            try context.save()
            let operation = UUID(), profileHash = try SharedMediaAcquisitionEncoding.digest(profile.binding)
            let first = try Manifest.Page(version: 1, operationID: operation, profileSHA256: profileHash,
                ordinal: 0, previousSHA256: nil,
                entries: [.init(namespace: .authority, token: ".", kind: .directory, identity: "1:2")]).encoded(profile: profile)
            let last = try Manifest.Page(version: 1, operationID: operation, profileSHA256: profileHash,
                ordinal: 1, previousSHA256: SharedMediaAcquisitionEncoding.digest(first),
                entries: [.init(namespace: .capture, token: ".", kind: .absent, identity: nil)]).encoded(profile: profile)
            pages = [first, last]
            header = .init(version: 1, operation: .signOut, operationID: operation, profileSHA256: profileHash,
                storeFileIdentity: "1:9", storeParentIdentity: "1:10", controlParentIdentity: "1:11",
                parentReceiptSHA256: nil, controlSHA256: String(repeating: "c", count: 64), sourceRevision: 7,
                sourceTables: try SharedMediaNativeErasureGraph.snapshot(context, checkpoint: {}),
                pageCount: 2, entryCount: 2, lastPageSHA256: SharedMediaAcquisitionEncoding.digest(last))
        }

        deinit { if let directoryURL { try? FileManager.default.removeItem(at: directoryURL) } }

        func begin(boundary: (Journal.Boundary) throws -> Void = { _ in }) throws -> Journal.Snapshot {
            try Journal.begin(header, container: container, profile: profile, checkpoint: {}, boundary: boundary)
        }
        func append(_ index: Int, boundary: (Journal.Boundary) throws -> Void = { _ in }) throws -> Journal.Snapshot {
            try Journal.append(pages[index], container: container, profile: profile,
                operationID: header.operationID, checkpoint: {}, boundary: boundary)
        }
        func retire() throws -> Journal.Snapshot {
            try Journal.retire(container: container, profile: profile, operationID: header.operationID, checkpoint: {})
        }
        func read() throws -> Journal.Snapshot {
            try Journal.read(container: container, profile: profile, operationID: header.operationID, checkpoint: {})
        }
        func complete(absence: (Journal.Header) throws -> Void = { _ in },
                      boundary: (Journal.Boundary) throws -> Void = { _ in }) throws -> Journal.Snapshot {
            try Journal.qualificationComplete(container: container, profile: profile, operationID: header.operationID,
                checkpoint: {}, verifyAbsence: absence, boundary: boundary)
        }
        func clear(absence: (Journal.Header) throws -> Void = { _ in },
                   boundary: (Journal.Boundary) throws -> Void = { _ in }) throws -> Journal.Snapshot {
            try Journal.qualificationClear(container: container, profile: profile, operationID: header.operationID,
                checkpoint: {}, verifyAbsence: absence, boundary: boundary)
        }
    }
}
