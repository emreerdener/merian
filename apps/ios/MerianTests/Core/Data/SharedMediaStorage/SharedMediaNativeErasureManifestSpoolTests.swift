import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
struct NativeErasureManifestSpoolTests {
    typealias Spool = SharedMediaNativeErasureManifestSpool
    typealias Manifest = SharedMediaNativeErasureManifest

    @Test func unorderedLargeManifestProducesRepeatableCanonicalPages() async throws {
        let profile = profile(), operation = UUID()
        let entries = (0..<513).map { _ in
            Manifest.Entry(namespace: .photo,
                token: "PhotoPreparation/\(profile.ownerID.uuidString.lowercased())/\(UUID().uuidString.lowercased())",
                kind: .directory, identity: "1:2")
        }.sorted { $0.key > $1.key }
        let first = try Spool(ownerID: profile.ownerID, checkpoint: {})
        let second = try Spool(ownerID: profile.ownerID, checkpoint: {})
        for entry in entries { try first.append(entry) }
        for entry in entries.reversed() { try second.append(entry) }
        try await first.seal(); try await second.seal()
        var pages: [Data] = [], replay: [Data] = [], reordered: [Data] = []
        let chain = try await first.visitPages(profile: profile, operationID: operation) { pages.append($0) }
        _ = try await first.visitPages(profile: profile, operationID: operation) { replay.append($0) }
        _ = try await second.visitPages(profile: profile, operationID: operation) { reordered.append($0) }
        #expect(pages == replay && pages == reordered)
        #expect(chain.entryCount == 513 && chain.pageCount == 5)
        let decoded = try pages.flatMap { try Manifest.Page.decode($0, profile: profile).entries }
        #expect(decoded == entries.reversed())
        #expect(throws: (any Error).self) { try first.append(entries[0]) }
        // Removed package rows do not bound the empty directories left behind.
        // This is codec coverage only; namespace ownership is audited separately.
        let schema = Schema(SharedMediaNativeErasureGraph.modelTypes + SharedMediaNativeErasureGraph.carrierModelTypes
            + [SharedMediaInventoryRecord.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = ModelContext(container); context.autosaveEnabled = false
        let tables = try SharedMediaNativeErasureGraph.snapshot(context, checkpoint: {})
        #expect(tables.allSatisfy { $0.rows == 0 })
        let header = SharedMediaNativeErasureHeader(version: 1, operation: .accountDeletion, operationID: operation,
            profileSHA256: try SharedMediaAcquisitionEncoding.digest(profile.binding), storeFileIdentity: "1:3",
            storeParentIdentity: "1:4", controlParentIdentity: "1:5", parentReceiptSHA256: nil,
            controlSHA256: String(repeating: "c", count: 64), sourceRevision: 0, sourceTables: tables,
            pageCount: chain.pageCount, entryCount: chain.entryCount, lastPageSHA256: try #require(chain.digest))
        #expect(try SharedMediaNativeErasureHeader.decode(header.encoded(profile: profile), profile: profile) == header)
    }

    @Test(arguments: [false, true]) func duplicateInSameOrDifferentRunPoisonsSpool(differentRun: Bool) async throws {
        let profile = profile(), spool = try Spool(ownerID: profile.ownerID, checkpoint: {})
        let entry = Manifest.Entry(namespace: .authority, token: ".", kind: .directory, identity: "1:2")
        try spool.append(entry)
        if differentRun {
            for _ in 0..<128 {
                try spool.append(.init(namespace: .capture, token: "CaptureArtifacts/" + UUID().uuidString.lowercased(),
                    kind: .absent, identity: nil))
            }
        }
        try spool.append(entry)
        await #expect(throws: (any Error).self) { try await spool.seal() }
        await #expect(throws: (any Error).self) { _ = try await spool.visitPages(profile: profile, operationID: UUID()) { _ in } }
    }

    @Test func revokedScopeAndForeignOwnerCannotYieldPages() async throws {
        let profile = profile()
        var current = true
        let spool = try Spool(ownerID: profile.ownerID, checkpoint: {
            guard current else { throw SharedMediaStorageFailure.stale }
        })
        try spool.append(.init(namespace: .authority, token: ".", kind: .absent, identity: nil))
        try await spool.seal()
        await #expect(throws: (any Error).self) { _ = try await spool.visitPages(profile: self.profile(), operationID: UUID()) { _ in } }
        current = false
        await #expect(throws: (any Error).self) { _ = try await spool.visitPages(profile: profile, operationID: UUID()) { _ in } }
    }

    @Test func emptyOrInvalidBuildCannotBeAdopted() async throws {
        let profile = profile(), empty = try Spool(ownerID: profile.ownerID, checkpoint: {})
        await #expect(throws: (any Error).self) { try await empty.seal() }
        let invalid = try Spool(ownerID: profile.ownerID, checkpoint: {})
        #expect(throws: (any Error).self) {
            try invalid.append(.init(namespace: .photo, token: "PhotoPreparation/" + UUID().uuidString.lowercased(),
                kind: .directory, identity: "1:2"))
        }
        #expect(throws: (any Error).self) {
            try invalid.append(.init(namespace: .authority, token: ".", kind: .absent, identity: nil))
        }
    }

    private func profile() -> SharedMediaNativeAppProfile {
        .init(ownerID: UUID(), inventoryID: UUID(), generation: UUID(), storeIdentity: UUID().uuidString,
            physicalBinding: String(repeating: "a", count: 64), receiptDigest: String(repeating: "b", count: 64),
            physicalBindingFormat: .physicalRootsV1)
    }
}
