import Foundation
import SwiftData
import Testing
@testable import Merian

/// Storage foundation only. Raw fixtures deliberately bypass typed admission;
/// no row in this checkpoint authorizes receiving, execution or cleanup.
@Suite("Receiving intent storage foundation", .serialized)
@MainActor
struct SharedMediaReceivingIntentFoundationTests {
    @Test func everyRawPhaseBlocksLegacyPurgeAndForeignAccount() throws {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = ModelContext(container); context.autosaveEnabled = false
        for phase in ["prepared", "received", "abandoned", "malformed"] {
            let owner = UUID(), row = Self.row(owner: UUID()); row.phaseRaw = phase
            context.insert(row); try context.save()
            #expect(try SharedMediaStorageRepository.hasLiabilities(in: context))
            #expect(throws: SharedMediaStorageFailure.inUse) { try SharedMediaPurgeState.requireEmptyGraph(context) }
            #expect(throws: SharedMediaStorageFailure.closed) { try SharedMediaStorageLookup.requireNoNativeOwnership(context) }
            #expect(throws: PhotoPreparationFailure.unsupportedComposition) { _ = try PhotoPreparationRepository(container: container) }
            #expect(throws: SharedMediaStorageFailure.closed) { try SharedMediaNativeEligibility.requireOriginalAccount(context, ownerID: row.ownerID) }
            #expect(throws: SharedMediaStorageFailure.closed) { try SharedMediaNativeEligibility.requireOriginalAccount(context, ownerID: owner) }
            #expect(row.cursorKey == row.id.uuidString.lowercased())
            context.delete(row); try context.save()
            #expect(try !SharedMediaStorageRepository.hasLiabilities(in: context))
        }
    }

    @Test func scopedAuditRejectsOrphanAndAnInsertionAcrossPageSuspension() async throws {
        let (store, owner, request) = try await SharedMediaNativeAppReceivingTests().fixture()
        let context = store.context(), row = Self.row(owner: store.ownerID)
        context.insert(row); try context.save()
        func audit(_ betweenPages: @escaping () async throws -> Void) throws -> SharedMediaNativeScopedAudit {
            try SharedMediaNativeScopedAudit(app: store.container, profile: request.profile,
                expected: request.header.inventory, check: {}, betweenPages: betweenPages)
        }
        await #expect(throws: SharedMediaStorageFailure.closed) { _ = try await audit({}).run() }
        #expect(try context.fetchCount(FetchDescriptor<SharedMediaReceivingIntentRecord>()) == 1)
        context.delete(row); try context.save()
        var inserted = false
        let delayed = try audit {
            if !inserted {
                inserted = true
                let fresh = store.context(); fresh.insert(Self.row(owner: store.ownerID)); try fresh.save()
            }
        }
        await #expect(throws: SharedMediaStorageFailure.closed) { _ = try await delayed.run() }
        #expect(inserted)
        #expect(try store.context().fetchCount(FetchDescriptor<SharedMediaConsumerRecord>()) == 0)
        #expect(try store.package(in: store.context()).revision == request.package.revision)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func exactSlotFieldsAndOptionalPayloadsSurviveDiskReopen() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("receiving-slot-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("store.sqlite"), id = UUID(), owner = UUID()
        let inventory = UUID(), generation = UUID(), draft = UUID(), operation = UUID()
        let prepared = Data([0, 1, 127, 128, 255]), result = Data([255, 128, 1, 0])
        func open() throws -> ModelContainer {
            let schema = Schema(versionedSchema: CurrentSchema.self)
            return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
        }
        do {
            let container = try open(), context = ModelContext(container)
            let row = SharedMediaReceivingIntentRecord(packageID: id, inventoryID: inventory,
                inventoryGeneration: generation, ownerID: owner, draftGeneration: draft,
                operationID: operation, preparedData: prepared, preparedSHA256: String(repeating: "a", count: 64))
            row.phaseRaw = "received"; row.revision = 9
            row.resultData = result; row.resultSHA256 = String(repeating: "b", count: 64)
            context.insert(row); try context.save()
        }
        for clearPrepared in [true, false] {
            let container = try open(), context = ModelContext(container)
            let row = try #require(try context.fetch(FetchDescriptor<SharedMediaReceivingIntentRecord>()).first)
            #expect(row.id == id && row.cursorKey == id.uuidString.lowercased() && row.schemaVersion == 1)
            #expect(row.ownerID == owner && row.inventoryID == inventory && row.inventoryGeneration == generation)
            #expect(row.draftGeneration == draft && row.operationID == operation)
            #expect(row.preparedSHA256 == String(repeating: "a", count: 64))
            #expect(row.resultSHA256 == String(repeating: "b", count: 64) && row.resultData == result)
            #expect(row.preparedData == (clearPrepared ? prepared : nil))
            #expect(row.phaseRaw == (clearPrepared ? "received" : "abandoned"))
            #expect(row.revision == (clearPrepared ? 9 : 10))
            #expect(try SharedMediaStorageRepository.hasLiabilities(in: context))
            if clearPrepared {
                // Raw storage-shape check, not an authorized abandonment transition.
                row.phaseRaw = "abandoned"; row.revision = 10; row.preparedData = nil; try context.save()
            }
        }
    }

    private static func row(owner: UUID) -> SharedMediaReceivingIntentRecord {
        .init(packageID: UUID(), inventoryID: UUID(), inventoryGeneration: UUID(), ownerID: owner,
              draftGeneration: UUID(), operationID: UUID(), preparedData: Data("invalid fixture".utf8),
              preparedSHA256: "malformed")
    }
}
