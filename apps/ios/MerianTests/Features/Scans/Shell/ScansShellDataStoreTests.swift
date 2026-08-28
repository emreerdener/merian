import SwiftData
import XCTest

@testable import Merian

@MainActor
final class ScansShellDataStoreTests: XCTestCase {
    func testQueueProjectionHidesCompletedAndNonRunnableRows() throws {
        let context = try makeContext()
        let active = OfflineQueuedScan(
            id: "active",
            timestamp: Date(timeIntervalSinceReferenceDate: 4),
            scanState: .pending
        )
        let needsAttention = OfflineQueuedScan(
            id: "needs-attention",
            timestamp: Date(timeIntervalSinceReferenceDate: 3),
            scanState: .failed,
            queueLastErrorMessage: "Restore or delete this scan.",
            queueNeedsAttention: true
        )
        let completed = OfflineQueuedScan(
            id: "completed",
            timestamp: Date(timeIntervalSinceReferenceDate: 2),
            scanState: .pending
        )
        let legacyImport = OfflineQueuedScan(
            id: "legacy-import",
            timestamp: Date(timeIntervalSinceReferenceDate: 1),
            scanState: .externalImport,
            queueNeedsAttention: false
        )
        context.insert(active)
        context.insert(needsAttention)
        context.insert(completed)
        context.insert(legacyImport)
        context.insert(makeRecord(id: "completed", timestamp: completed.timestamp))
        try context.save()

        let result = ScansShellDataStore().queuedSnapshots(
            in: context.container
        )

        XCTAssertEqual(result.snapshots.map(\.id), ["active", "needs-attention"])
        XCTAssertEqual(result.fetchedCount, 3)
        XCTAssertEqual(result.completedCount, 1)
        XCTAssertEqual(result.stateSummary, "0:2,5:1")
        XCTAssertEqual(result.visibleIDSummary, "active,needs-attention")
        XCTAssertEqual(
            result.snapshots.last?.queueLastErrorMessage,
            "Restore or delete this scan."
        )
    }

    func testRecordQueriesApplyBiologicalSelectionAndLimitPolicies() throws {
        let context = try makeContext()
        let oldest = makeRecord(
            id: "oldest",
            timestamp: Date(timeIntervalSinceReferenceDate: 1)
        )
        let newest = makeRecord(
            id: "newest",
            timestamp: Date(timeIntervalSinceReferenceDate: 3)
        )
        let nonBiological = makeRecord(
            id: "non-biological",
            timestamp: Date(timeIntervalSinceReferenceDate: 2),
            isBiological: false
        )
        context.insert(oldest)
        context.insert(newest)
        context.insert(nonBiological)
        try context.save()
        let store = ScansShellDataStore()

        XCTAssertEqual(
            store.biologicalRecords(in: context).map(\.id),
            ["newest", "oldest"]
        )
        XCTAssertEqual(
            store.selectedRecords(
                ids: ["oldest", "newest"],
                limit: 1,
                in: context
            ).map(\.id),
            ["newest"]
        )
    }

    func testDeletionUsesInjectedRepositoryBoundaryInOrder() throws {
        let context = try makeContext()
        let first = makeRecord(
            id: "first",
            timestamp: Date(timeIntervalSinceReferenceDate: 2)
        )
        let second = makeRecord(
            id: "second",
            timestamp: Date(timeIntervalSinceReferenceDate: 1)
        )
        var deletedIDs: [String] = []
        let store = ScansShellDataStore(
            dependencies: .init(
                eradicateScan: { record, receivedContext in
                    XCTAssertTrue(receivedContext === context)
                    deletedIDs.append(record.id)
                }
            )
        )

        store.delete(records: [first, second], in: context)

        XCTAssertEqual(deletedIDs, ["first", "second"])
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema(CurrentSchema.models)
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        return ModelContext(container)
    }

    private func makeRecord(
        id: String,
        timestamp: Date,
        isBiological: Bool = true
    ) -> LocalScanRecord {
        LocalScanRecord(
            id: id,
            speciesId: "species-\(id)",
            scientificName: "Species \(id)",
            commonName: "Species \(id)",
            timestamp: timestamp,
            isBiological: isBiological
        )
    }
}
