import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
struct NativeErasureAuditTests {
    typealias Store = SharedMediaCaptureArtifactLedgerTests.Store

    @Test(arguments: ["reserved", "writing", "ready"])
    func initialAuditIncludesCaptureAndRejectsUnanchoredRows(_ phase: String) async throws {
        let store = try SharedMediaCaptureArtifactFilesTests.Store(fullSchema: true)
        if phase == "writing" { _ = try store.begin(); try Data([7, 7]).write(to: store.partial) }
        if phase == "ready" { _ = try store.finish() }
        let container = store.ledger.container, profile = store.request.profile
        func audit() async throws -> SharedMediaNativeScopedSnapshot {
            try await SharedMediaNativeScopedAudit.runAppErasureInitial(container: container, profile: profile,
                files: store.files, header: { try Self.header(container, profile) }, betweenPages: {})
        }
        #expect(try await audit().allocations == 1)
        let context = ModelContext(container); context.autosaveEnabled = false
        context.insert(SharedMediaLeaseRecord(id: UUID(), allocationID: UUID(), processEpoch: UUID(),
            purposeRaw: "captureArtifactV1", stateRaw: "closed"))
        try context.save()
        await #expect(throws: (any Error).self) { _ = try await audit() }
        #expect(try context.fetchCount(FetchDescriptor<SharedMediaLeaseRecord>()) == 2)
        #expect(try context.fetchCount(FetchDescriptor<SharedMediaNativeErasurePageRecord>()) == 0)
    }

    @Test(arguments: [false, true])
    func initialAuditAcceptsActualReceivingStagesWithoutRelaxingOrdinaryReaders(received: Bool) async throws {
        let (store, owner, request) = try await SharedMediaNativeAppReceivingTests().fixture(count: 1, staged: true)
        if received { _ = try await owner.receiveAppPhotos(request) }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let profile = request.profile, container = store.container
        await #expect(throws: (any Error).self) {
            _ = try await SharedMediaNativeScopedAudit.runAppErasureInitial(container: container, profile: profile,
                files: nil, header: { try Self.header(container, profile) }, betweenPages: {})
        }
        // The metadata fixture deliberately seeds an opaque, unanchored row
        // that scoped readers ignore. Whole-store erasure must reject it.
        let seed = store.context()
        let detached = try store.package(store.ordinaryID, in: seed)
        #expect(detached.supportingContextData == Data("ordinary-draft".utf8))
        seed.delete(detached); try seed.save()
        let result = try await SharedMediaNativeScopedAudit.runAppErasureInitial(container: container, profile: profile,
            files: nil, header: { try Self.header(container, profile) }, betweenPages: {})
        #expect(result.receipts == 1 && result.allocations == 3)
        let context = ModelContext(container); context.autosaveEnabled = false
        let slot = try #require(try context.fetch(FetchDescriptor<SharedMediaReceivingIntentRecord>()).first)
        slot.preparedSHA256 = String(repeating: "0", count: 64); try context.save()
        await #expect(throws: (any Error).self) {
            _ = try await SharedMediaNativeScopedAudit.runAppErasureInitial(container: container, profile: profile,
                files: nil, header: { try Self.header(container, profile) }, betweenPages: {})
        }
    }

    private static func header(_ container: ModelContainer, _ profile: SharedMediaNativeAppProfile) throws -> SharedMediaNativeAppEligibility.Header {
        try SharedMediaNativeAppEligibility.snapshot(context: ModelContext(container), scope: .init(
            inventoryID: profile.inventoryID, generation: profile.generation, ownerID: profile.ownerID,
            storeIdentity: profile.storeIdentity, rootBinding: try profile.rootIdentity))
    }

    @Test func initialCaptureAuditRejectsExistingErasureCarrier() async throws {
        let store = try SharedMediaCaptureArtifactFilesTests.Store(fullSchema: true)
        _ = try store.finish()
        let container = store.ledger.container, profile = store.request.profile
        let context = ModelContext(container); context.autosaveEnabled = false
        context.insert(SharedMediaNativeErasurePageRecord(operationID: UUID(), inventoryID: profile.inventoryID,
            inventoryGeneration: profile.generation, ownerID: profile.ownerID,
            profileSHA256: try SharedMediaAcquisitionEncoding.digest(profile.binding), kindRaw: "header", ordinal: -1,
            bodyData: Data(), bodySHA256: String(repeating: "0", count: 64)))
        try context.save()
        await #expect(throws: (any Error).self) {
            _ = try await SharedMediaNativeScopedAudit.runAppErasureInitial(container: container, profile: profile,
                files: store.files, header: { try Self.header(container, profile) }, betweenPages: {})
        }
        #expect(try context.fetchCount(FetchDescriptor<SharedMediaNativeErasurePageRecord>()) == 1)
        #expect(FileManager.default.fileExists(atPath: store.final.path))
    }

    @Test(arguments: [SharedMediaCaptureArtifactLedger.Phase.reserved, .writing, .ready])
    func cleanupInspectionPreservesJoinsWithoutReopeningNormalAdmission(phase: SharedMediaCaptureArtifactLedger.Phase) async throws {
        let store = try Store(phase: phase, fullSchema: true)
        let expected = try store.read(), operation = try prepare(store)
        var escaped: SharedMediaNativeErasureAuditScope?
        try await SharedMediaNativeErasureAuditScope.withVerified(container: store.container, profile: store.request.profile,
            operationID: operation, checkpoint: {}) { scope in
            escaped = scope
            let context = ModelContext(store.container)
            #expect(throws: (any Error).self) { try store.read(context: context) }
            let value = try SharedMediaCaptureArtifactLedger.auditErasureRead(id: store.request.id, profile: store.request.profile,
                rootBindingSHA256: store.request.rootBindingSHA256, context: context, erasure: scope)
            #expect(value == expected)
            let inventory = try SharedMediaCaptureArtifactStoreAudit.verifyForErasure(context: context, erasure: scope,
                rootBindingSHA256: store.request.rootBindingSHA256, checkpoint: {}, inspectArtifact: { #expect($0 == expected) })
            #expect(inventory.artifacts == 1)
        }
        let expired = try #require(escaped)
        #expect(throws: (any Error).self) { try expired.requireCurrent(ModelContext(store.container)) }
    }

    @Test func cleanupInspectionRejectsChangedSourceGraphAndOperation() async throws {
        let store = try Store(fullSchema: true), operation = try prepare(store)
        await #expect(throws: (any Error).self) {
            try await SharedMediaNativeErasureAuditScope.withVerified(container: store.container, profile: store.request.profile,
                operationID: UUID(), checkpoint: {}) { _ in Issue.record("Foreign operation entered cleanup inspection") }
        }
        await #expect(throws: (any Error).self) {
            try await SharedMediaNativeErasureAuditScope.withVerified(container: store.container, profile: store.request.profile,
                operationID: operation, checkpoint: {}) { scope in
                let context = ModelContext(store.container); context.autosaveEnabled = false
                let row = try #require(try context.fetch(FetchDescriptor<SharedMediaLeaseRecord>()).first)
                row.stateRaw = "foreign"
                try context.save()
                #expect(throws: (any Error).self) {
                    try SharedMediaCaptureArtifactLedger.auditErasureRead(id: store.request.id, profile: store.request.profile,
                        rootBindingSHA256: store.request.rootBindingSHA256, context: ModelContext(store.container), erasure: scope)
                }
            }
        }
    }

    private func prepare(_ store: Store) throws -> UUID {
        let profile = store.request.profile, operation = UUID()
        let bytes = try SharedMediaNativeErasureManifest.Page(version: 1, operationID: operation,
            profileSHA256: SharedMediaAcquisitionEncoding.digest(profile.binding), ordinal: 0, previousSHA256: nil,
            entries: [.init(namespace: .authority, token: ".", kind: .absent, identity: nil)]).encoded(profile: profile)
        let context = ModelContext(store.container)
        let inventory = try #require(try context.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first)
        let header = SharedMediaNativeErasureHeader(version: 1, operation: .accountDeletion, operationID: operation,
            profileSHA256: try SharedMediaAcquisitionEncoding.digest(profile.binding), storeFileIdentity: "1:2",
            storeParentIdentity: "1:3", controlParentIdentity: "1:4", parentReceiptSHA256: nil,
            controlSHA256: String(repeating: "a", count: 64), sourceRevision: inventory.revision,
            sourceTables: try SharedMediaNativeErasureGraph.snapshot(context, checkpoint: {}),
            pageCount: 1, entryCount: 1, lastPageSHA256: SharedMediaAcquisitionEncoding.digest(bytes))
        _ = try SharedMediaNativeErasureJournal.begin(header, container: store.container, profile: profile, checkpoint: {})
        _ = try SharedMediaNativeErasureJournal.append(bytes, container: store.container, profile: profile,
            operationID: operation, checkpoint: {})
        return operation
    }

    @Test(arguments: ["reserved", "writing", "ready"])
    func physicalCleanupAuditKeepsWholeStoreJoinsAndExpires(_ phase: String) async throws {
        let store = try SharedMediaCaptureArtifactFilesTests.Store(fullSchema: true)
        if phase == "writing" { _ = try store.begin(); try Data([7, 7]).write(to: store.partial) }
        if phase == "ready" { _ = try store.finish() }
        let before = try await store.audit(), operation = try prepare(store.ledger)
        let container = store.ledger.container
        var escaped: SharedMediaCaptureAuditEvidence?
        try await SharedMediaNativeErasureAuditScope.withVerified(container: container, profile: store.request.profile,
            operationID: operation, checkpoint: {}) { scope in
            try await SharedMediaCaptureAuditEvidence.withErasure(container: container, scope: scope,
                files: store.files, checkpoint: {}) { capture in
                escaped = capture
                #expect(capture.inventory.physicalBytes == before.physicalBytes)
                #expect(capture.inventory.ledger.artifacts == before.ledger.artifacts)
                let ordinary = try SharedMediaOrdinaryStoreAudit.verifyForErasure(context: ModelContext(container),
                    erasure: scope, capture: capture, checkpoint: {})
                #expect(ordinary.submissions == 0 && ordinary.holds == 0)
                await #expect(throws: (any Error).self) { _ = try await store.audit() }
            }
        }
        let stale = try #require(escaped)
        #expect(throws: (any Error).self) { try stale.requireCurrent(ModelContext(container)) }
    }

    @Test(arguments: ["ambiguous", "missing", "changedBytes", "foreignLeaf"])
    func physicalCleanupAuditCannotAdoptUnprovenFiles(_ mutation: String) async throws {
        let store = try SharedMediaCaptureArtifactFilesTests.Store(fullSchema: true)
        if mutation != "ambiguous" { _ = try store.finish() }
        let operation = try prepare(store.ledger)
        switch mutation {
        case "ambiguous": try Data().write(to: store.partial)
        case "missing": try FileManager.default.removeItem(at: store.final)
        case "changedBytes": try Data(repeating: 8, count: 48).write(to: store.final)
        case "foreignLeaf": try Data([1]).write(to: store.namespace.appendingPathComponent(UUID().uuidString.lowercased()))
        default: Issue.record("Unexpected mutation")
        }
        await #expect(throws: (any Error).self) {
            try await SharedMediaNativeErasureAuditScope.withVerified(container: store.ledger.container,
                profile: store.request.profile, operationID: operation, checkpoint: {}) { scope in
                try await SharedMediaCaptureAuditEvidence.withErasure(container: store.ledger.container, scope: scope,
                    files: store.files, checkpoint: {}) { _ in Issue.record("Unproven file entered cleanup audit") }
            }
        }
    }
}
