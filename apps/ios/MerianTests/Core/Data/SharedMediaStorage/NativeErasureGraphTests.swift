import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
struct NativeErasureGraphTests {
    private func container() throws -> ModelContainer {
        let schema = Schema(SharedMediaNativeErasureGraph.modelTypes + SharedMediaNativeErasureGraph.carrierModelTypes + [SharedMediaInventoryRecord.self])
        return try ModelContainer(for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    }

    private func asset(id: UUID = UUID()) -> PhotoPreparationAsset {
        .init(id: id, ownerID: UUID(), generation: UUID(), fileToken: "synthetic",
            contentType: "image/jpeg", byteCount: 3, sha256: String(repeating: "a", count: 64),
            acquisitionKindRaw: "synthetic", cleanupStateRaw: "retired")
    }

    @Test func everyNativeTableIsIncludedEvenWhenEmpty() throws {
        let container = try container(), context = ModelContext(container)
        context.autosaveEnabled = false
        let value = try SharedMediaNativeErasureGraph.snapshot(context, checkpoint: {})
        let expected = SharedMediaStorageLookup.photoTypes.union(SharedMediaStorageLookup.inboxTypes)
            .union(SharedMediaStorageLookup.ledgerTypes).subtracting([ObjectIdentifier(SharedMediaInventoryRecord.self)] + SharedMediaNativeErasureGraph.carrierModelTypes.map(ObjectIdentifier.init))
        #expect(Set(SharedMediaNativeErasureGraph.modelTypes.map(ObjectIdentifier.init)) == expected)
        #expect(value.count == expected.count && value.allSatisfy { $0.rows == 0 })
        #expect(Set(value.map(\.sha256)).count == value.count)
    }

    @Test func unknownPersistedColumnIsRejectedOnAnEmptyTable() throws {
        let container = try container(), context = ModelContext(container)
        context.autosaveEnabled = false
        let entity = try #require(container.schema.entities.first { $0.name == "PhotoPreparationAsset" })
        let saved = entity.storedProperties
        defer { entity.storedProperties = saved }
        entity.storedProperties.append(Schema.Attribute(name: "futureOwnership", valueType: String?.self))
        #expect(throws: SharedMediaStorageFailure.conflict) {
            try SharedMediaNativeErasureGraph.snapshot(context, checkpoint: {})
        }
    }

    @Test(arguments: [false, true])
    func separateContextRevisionChangeBetweenPagesIsRejected(insert: Bool) throws {
        let container = try container(), context = ModelContext(container)
        context.autosaveEnabled = false
        let inventoryID = UUID()
        context.insert(SharedMediaInventoryRecord(id: inventoryID, rootIdentity: "synthetic", storeIdentity: "synthetic",
            generation: UUID(), revision: 0, modeRaw: "synthetic", phaseRaw: "synthetic", cursor: ""))
        for _ in 0...SharedMediaStoragePolicy.pageSize { context.insert(asset()) }
        try context.save()
        var checkpoints = 0
        #expect(throws: SharedMediaStorageFailure.stale) {
            try SharedMediaNativeErasureGraph.snapshot(context, checkpoint: {
                checkpoints += 1
                let fresh = ModelContext(container); fresh.autosaveEnabled = false
                let row = try #require(try fresh.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first)
                if checkpoints == 3 {
                    if insert { fresh.insert(asset()) } else {
                        let removed = try #require(try fresh.fetch(FetchDescriptor<PhotoPreparationAsset>()).first)
                        fresh.delete(removed)
                    }
                    row.revision += 1; try fresh.save()
                }
                guard row.revision == 0 else { throw SharedMediaStorageFailure.stale }
            })
        }
        #expect(checkpoints == 3 && !context.hasChanges)
    }

    @Test func pagedRetiredAndForeignRowsCannotDisappearFromSnapshot() throws {
        let container = try container(), context = ModelContext(container)
        context.autosaveEnabled = false
        for _ in 0...SharedMediaStoragePolicy.pageSize { context.insert(asset()) }
        try context.save()
        let original = try SharedMediaNativeErasureGraph.snapshot(context, checkpoint: {})
        #expect(original.first { $0.name == "PhotoPreparationAsset" }?.rows == Int64(SharedMediaStoragePolicy.pageSize + 1))
        let fresh = ModelContext(container); fresh.autosaveEnabled = false
        #expect(try SharedMediaNativeErasureGraph.snapshot(fresh, checkpoint: {}) == original)
        let row = try #require(try fresh.fetch(FetchDescriptor<PhotoPreparationAsset>(sortBy: [SortDescriptor(\.id)])).last)
        row.cleanupStateRaw = "unknown-future-state"; try fresh.save()
        #expect(try SharedMediaNativeErasureGraph.snapshot(fresh, checkpoint: {}) != original)
        fresh.delete(row); try fresh.save()
        #expect(try SharedMediaNativeErasureGraph.snapshot(fresh, checkpoint: {}) != original)
    }

    @Test func binaryChangesAndUncommittedRowsAreNotIgnored() throws {
        let container = try container(), context = ModelContext(container)
        context.autosaveEnabled = false
        let record = PhotoPreparationRecord(id: UUID(), ownerID: UUID(), contractVersion: "synthetic",
            draftID: UUID(), draftGeneration: UUID(), revision: 0, phaseRaw: "retired",
            supportingContextData: Data([1, 2, 3]), allocatedByteCount: 0, retirementRequested: true)
        context.insert(record)
        #expect(throws: (any Error).self) { try SharedMediaNativeErasureGraph.snapshot(context, checkpoint: {}) }
        try context.save()
        let first = try SharedMediaNativeErasureGraph.snapshot(context, checkpoint: {})
        record.supportingContextData = Data([1, 2, 4]); try context.save()
        #expect(try SharedMediaNativeErasureGraph.snapshot(context, checkpoint: {}) != first)
    }

    @Test func revokedCheckpointProducesNoSnapshot() throws {
        let container = try container(), context = ModelContext(container)
        context.autosaveEnabled = false
        var calls = 0
        #expect(throws: SharedMediaStorageFailure.closed) {
            try SharedMediaNativeErasureGraph.snapshot(context, checkpoint: {
                calls += 1
                if calls == 3 { throw SharedMediaStorageFailure.closed }
            })
        }
        #expect(calls == 3 && !context.hasChanges)
    }
}
