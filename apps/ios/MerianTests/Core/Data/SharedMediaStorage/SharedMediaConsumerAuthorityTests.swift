import Foundation
@testable import Merian
import SwiftData
import Testing

@Suite(.serialized)
@MainActor
struct SharedMediaConsumerAuthorityTests {
    @Test func malformedAuthorityCannotBecomeLegacy() throws {
        let id = UUID()
        for record in [SharedMediaConsumerAuthority.RecordKind.queue, .scan, .analysis] {
            #expect(try SharedMediaConsumerAuthority.classify(raw: "legacy", consumerID: nil, record: record) == .legacy)
            #expect(try SharedMediaConsumerAuthority.classify(raw: "sharedDirectV1", consumerID: id, record: record) == .direct(id))
            for (raw, value) in [("legacy", id as UUID?), ("sharedDirectV1", nil), ("unknown", nil), ("unknown", id)] {
                #expect(throws: SharedMediaStorageFailure.conflict) {
                    try SharedMediaConsumerAuthority.classify(raw: raw, consumerID: value, record: record)
                }
            }
        }
        #expect(try SharedMediaConsumerAuthority.classify(raw: "sharedHistoryProjectionV1", consumerID: nil, record: .scan) == .historyProjection)
        for record in [SharedMediaConsumerAuthority.RecordKind.queue, .analysis] {
            #expect(throws: SharedMediaStorageFailure.conflict) {
                try SharedMediaConsumerAuthority.classify(raw: "sharedHistoryProjectionV1", consumerID: nil, record: record)
            }
        }
        #expect(throws: SharedMediaStorageFailure.conflict) {
            try SharedMediaConsumerAuthority.classify(raw: "sharedHistoryProjectionV1", consumerID: id, record: .scan)
        }
    }

    @Test func nativeReceivingHasDistinctAuthorityWithoutLegacyFallback() throws {
        let id = UUID()
        #expect(try SharedMediaConsumerAuthority.classify(raw: "sharedDirectNativeReceivingV1", consumerID: id,
            record: .queue) == .nativeDirect(id))
        #expect(try SharedMediaConsumerAuthority.classify(raw: "sharedDirectV1", consumerID: id,
            record: .queue) == .direct(id))
        #expect(throws: SharedMediaStorageFailure.conflict) {
            try SharedMediaConsumerAuthority.classify(raw: "sharedDirectNativeReceivingV1", consumerID: nil, record: .queue)
        }
    }

    @Test func retainedInitialAuthorityIsScanOnlyAndNeverLegacy() throws {
        let id = UUID()
        #expect(try SharedMediaConsumerAuthority.classify(raw: "sharedDirectNativeInitialV1", consumerID: id,
            record: .scan) == .nativeInitial(id))
        for kind in [SharedMediaConsumerAuthority.RecordKind.queue, .analysis] {
            #expect(throws: SharedMediaStorageFailure.conflict) {
                try SharedMediaConsumerAuthority.classify(raw: "sharedDirectNativeInitialV1", consumerID: id, record: kind)
            }
        }
        #expect(throws: SharedMediaStorageFailure.conflict) {
            try SharedMediaConsumerAuthority.classify(raw: "sharedDirectNativeInitialV1", consumerID: nil, record: .scan)
        }
        #expect(try SharedMediaConsumerAuthority.classify(raw: "legacy", consumerID: nil, record: .scan) == .legacy)
    }

    @Test func ordinaryAndReanalysisExecutionRemainDistinct() throws {
        let generation = UUID()
        #expect(try SharedMediaConsumerExecution.classify(raw: "ordinaryV1", generation: generation) == .ordinary(generation))
        #expect(try SharedMediaConsumerExecution.classify(raw: "reanalysisV1", generation: nil) == .reanalysis)
        for (raw, value) in [("ordinaryV1", nil as UUID?), ("reanalysisV1", generation), ("unknown", nil)] {
            #expect(throws: SharedMediaStorageFailure.conflict) {
                try SharedMediaConsumerExecution.classify(raw: raw, generation: value)
            }
        }
    }

    @Test func sharedQueueCannotEnterLegacyInference() {
        let queue = OfflineQueuedScan()
        #expect(queue.permitsOrdinaryInference)
        queue.sharedMediaConsumerID = UUID()
        #expect(!queue.permitsOrdinaryInference)
        queue.mediaAuthorityRaw = "sharedDirectV1"
        #expect(!queue.permitsOrdinaryInference)
        queue.sharedMediaConsumerID = nil
        #expect(!queue.permitsOrdinaryInference)
        queue.mediaAuthorityRaw = "unknown"
        #expect(!queue.permitsOrdinaryInference)
    }

    @Test func orphanConsumerBlocksLegacyOwnerAndEmptyPurgeClaim() throws {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let row = Self.consumer()
        context.insert(row); try context.save()
        #expect(try SharedMediaStorageRepository.hasLiabilities(in: context))
        #expect(throws: SharedMediaStorageFailure.inUse) { try SharedMediaPurgeState.requireEmptyGraph(context) }
        #expect(throws: PhotoPreparationFailure.unsupportedComposition) { _ = try PhotoPreparationRepository(container: container) }
        #expect(row.cursorKey == row.id.uuidString.lowercased())
        // An orphan is a liability even when there is no matching inventory/package row.
        context.delete(row); try context.save()
        #expect(try !SharedMediaStorageRepository.hasLiabilities(in: context))
    }

    @Test func diskKeysetDeletionAndPendingMembershipStayBounded() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("consumer-lookup-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // Keep the synthetic SQLite store through process exit: Core Data may retain WAL handles.
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema,
            url: root.appendingPathComponent("fixture.store"))])
        var ids = Set<UUID>()
        do {
            let context = ModelContext(container)
            context.autosaveEnabled = false
            let adversarial = ["a2b00000-0000-4000-8000-000000000001", "a10b0000-0000-4000-8000-000000000002"].map { UUID(uuidString: $0)! }
            for index in 0..<(SharedMediaStoragePolicy.pageSize + 3) {
                let row = Self.consumer(id: index < adversarial.count ? adversarial[index] : UUID())
                ids.insert(row.id); context.insert(row)
            }
            for index in 0..<12 {
                let id = UUID()
                let row = PhotoPreparationRecord(id: id, ownerID: UUID(), contractVersion: PhotoPreparationPolicy.contract,
                    draftID: id, draftGeneration: UUID(), revision: 0, phaseRaw: "preparedHeld",
                    supportingContextData: Data(), allocatedByteCount: 0, retirementRequested: false)
                row.accountingTierRaw = index < 4 ? "pending" : "retained"
                context.insert(row)
            }
            try context.save()
        }
        var cursor: String?
        var deleted = Set<UUID>()
        while true {
            // Fresh context emulates restart after each committed page, without offsets.
            let context = ModelContext(container)
            context.autosaveEnabled = false
            let page = try SharedMediaConsumerLookup.page(context, after: cursor)
            guard !page.isEmpty else { break }
            #expect(page.count <= SharedMediaStoragePolicy.pageSize)
            #expect(page.map(\.cursorKey) == page.map(\.cursorKey).sorted())
            for row in page {
                #expect(try SharedMediaConsumerLookup.one(context, id: row.id)?.packageID == row.packageID)
                #expect(try SharedMediaConsumerLookup.one(context, packageID: row.packageID)?.id == row.id)
                #expect(deleted.insert(row.id).inserted)
            }
            cursor = try #require(page.last?.cursorKey)
            for row in page { context.delete(row) }
            try context.save()
        }
        #expect(deleted == ids)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        #expect(try SharedMediaConsumerLookup.pendingPackages(context).count == 4)
        let retained = try #require(context.fetch(FetchDescriptor<PhotoPreparationRecord>()).first { $0.accountingTierRaw == "retained" })
        retained.accountingTierRaw = "pending"; try context.save()
        #expect(throws: SharedMediaStorageFailure.capacity) { try SharedMediaConsumerLookup.pendingPackages(context) }
        #expect(throws: SharedMediaStorageFailure.conflict) { try SharedMediaConsumerLookup.page(context, after: "invalid") }
    }

    private static func consumer(id: UUID = UUID()) -> SharedMediaConsumerRecord {
        .init(id: id, kindRaw: "queue", consumerID: "synthetic-queue", originQueueID: "synthetic-queue",
              observationID: "synthetic-observation", inventoryID: UUID(), inventoryGeneration: UUID(),
              ownerID: UUID(), packageID: UUID(), draftGeneration: UUID(), frozenPackageRevision: 1,
              contractVersion: "photoOriginalV1", digestVersion: 1, cohortSHA256: String(repeating: "a", count: 64),
              executionKindRaw: "ordinaryV1", inferenceGeneration: UUID())
    }
}
