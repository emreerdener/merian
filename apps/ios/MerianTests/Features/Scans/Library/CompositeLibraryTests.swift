import Foundation
import SwiftData
import Testing

@testable import Merian

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

    // MARK: - Test 2: new scans default to .pending state

    @Test func testQueueStateDefaultsPending() {
        let scan = OfflineQueuedScan()
        #expect(scan.queueState == .pending, "New scans must default to .pending so they are picked up by the next syncPendingScans pass")
    }

    // MARK: - Test 3: coverImagePath defaults to nil

    @Test func testCoverImagePathDefaultsToNil() throws {
        let scan = OfflineQueuedScan()
        #expect(scan.coverImagePath == nil, "coverImagePath must default to nil so ScanThumbnail receives nil gracefully")
    }

    // MARK: - Queue visibility and recovery eligibility

    @Test func testQueueVisibilitySeparatesRunnableAndUserRecoveryRows() throws {
        let context = try makeContext()

        // Mirror the exact predicate used in ScansSheetView.refreshQueuedScans().
        let active = OfflineQueuedScan(scanState: .pending)
        let legacyImport = OfflineQueuedScan(scanState: .externalImport)
        let purgeableFailure = OfflineQueuedScan(scanState: .failed)
        let recoverableFailure = OfflineQueuedScan(
            scanState: .failed,
            queueNeedsAttention: true
        )

        context.insert(active)
        context.insert(legacyImport)
        context.insert(purgeableFailure)
        context.insert(recoverableFailure)
        try context.save()

        let firstNonRunnableRaw = ScanQueueState.externalImport.rawValue
        var descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate {
                $0.scanStateRaw < firstNonRunnableRaw || $0.queueNeedsAttention
            }
        )
        descriptor.sortBy = [SortDescriptor(\.timestamp, order: .reverse)]
        let results = try context.fetch(descriptor)
        let resultIds = Set(results.map(\.id))

        #expect(resultIds == Set([active.id, recoverableFailure.id]))
        #expect(!resultIds.contains(legacyImport.id))
        #expect(!resultIds.contains(purgeableFailure.id))
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
        manager.filteredScans = manager.allScans  // performSearch is async (debounced); set directly for synchronous test

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
