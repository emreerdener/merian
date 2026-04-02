import Testing
@testable import Merian
import SwiftData
import Foundation

@MainActor
struct CompositeLibraryTests {

    // MARK: - Test Infrastructure

    private func makeContext() throws -> ModelContext {
        let schema = Schema(CurrentSchema.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    // MARK: - Test 1: OfflineQueuedScan IDs are unique across multiple inserts

    @Test func testOfflineQueuedScanIDsAreUnique() throws {
        let context = try makeContext()

        let scan1 = OfflineQueuedScan()
        let scan2 = OfflineQueuedScan()
        let scan3 = OfflineQueuedScan()

        context.insert(scan1)
        context.insert(scan2)
        context.insert(scan3)
        try context.save()

        let ids = [scan1.id, scan2.id, scan3.id]
        let uniqueIds = Set(ids)
        #expect(uniqueIds.count == ids.count, "Each OfflineQueuedScan must have a distinct id")
    }

    // MARK: - Test 2: isUploaded defaults to false

    @Test func testIsUploadedDefaultsFalse() {
        let scan = OfflineQueuedScan()
        #expect(scan.isUploaded == false, "isUploaded must default to false so existing records are not treated as already staged in R2")
    }

    // MARK: - Test 3: localImagePaths defaults to empty array

    @Test func testLocalImagePathsDefaultsToEmpty() throws {
        let scan = OfflineQueuedScan()
        #expect(scan.localImagePaths.isEmpty, "localImagePaths must default to [] so ScanThumbnail receives nil gracefully")
    }

    // MARK: - Test 3: isDeleted predicate excludes soft-deleted scans

    @Test func testDeletedScansExcludedByPredicate() throws {
        let context = try makeContext()

        let active = OfflineQueuedScan(isDeleted: false)
        let deleted = OfflineQueuedScan(isDeleted: true)

        context.insert(active)
        context.insert(deleted)
        try context.save()

        // Mirror the exact predicate used in ScansSheetView's @Query
        var descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { !$0.isDeleted }
        )
        descriptor.sortBy = [SortDescriptor(\.timestamp, order: .reverse)]
        let results = try context.fetch(descriptor)

        #expect(results.count == 1, "Predicate must exclude isDeleted=true records")
        #expect(results.first?.id == active.id, "Only the active scan should be returned")
    }

    // MARK: - Test 4: getSelectedLocalRecords() never returns entries for OfflineQueuedScan IDs

    @Test func testBatchSelectionEngineIsDecoupledFromOfflineQueue() throws {
        let context = try makeContext()

        // Insert a real LocalScanRecord
        let localScan = LocalScanRecord(
            id: UUID().uuidString,
            speciesId: UUID().uuidString,
            scientificName: "Testius birdius",
            commonName: "Test Bird",
            semanticTags: [],
            hazardType: "none",
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "wild",
            confidenceScore: 0.95,
            taxonomyKingdom: nil,
            taxonomyClass: nil,
            inferenceTier: "pro"
        )
        context.insert(localScan)
        try context.save()

        // Set up ScansManager with the local scan visible
        let manager = ScansManager()
        manager.allScans = [localScan]
        manager.performSearch(query: "")

        // Enter selection mode and inject an OfflineQueuedScan ID directly into selectedScans —
        // simulating the adversarial case where an offline scan ID somehow leaks into the set.
        let queuedScan = OfflineQueuedScan()
        manager.isSelectionMode = true
        manager.selectedScans.insert(queuedScan.id)
        manager.selectedScans.insert(localScan.id)

        let selected = manager.getSelectedLocalRecords()

        // getSelectedLocalRecords() filters from filteredScans (LocalScanRecord[]), so the
        // OfflineQueuedScan ID must not produce a result even if it appears in selectedScans.
        #expect(selected.count == 1, "Only LocalScanRecord entries should be returned by getSelectedLocalRecords()")
        #expect(selected.first?.id == localScan.id, "The queued scan ID must not match any LocalScanRecord")
        #expect(!selected.contains(where: { $0.id == queuedScan.id }), "Queued scan ID must be unreachable via the selection engine")
    }
}
