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

    private func makeCapturedMediaJSON(_ items: [SerializedMediaItem]) throws -> String {
        let data = try JSONEncoder().encode(items)
        return try #require(
            String(bytes: data, encoding: .utf8),
            "Captured media JSON must encode as UTF-8 text"
        )
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

    @Test func testVisibleNeedsAttentionRowsDoNotDriveAutomaticRecovery() {
        let attention = QueuedScanSnapshot(
            id: "needs-attention",
            imagePath: nil,
            capturedMediaJSON: nil,
            queueState: .failed,
            timestamp: Date(),
            queueNextRetryAt: nil,
            queueLastErrorMessage: "Restore or delete this scan.",
            queueNeedsAttention: true,
            approximateQueuedBytes: 0
        )
        let staged = QueuedScanSnapshot(
            id: "staged",
            imagePath: nil,
            capturedMediaJSON: nil,
            queueState: .staged,
            timestamp: Date(),
            queueNextRetryAt: nil,
            queueLastErrorMessage: nil,
            queueNeedsAttention: false,
            approximateQueuedBytes: 0
        )
        let legacyImport = QueuedScanSnapshot(
            id: "legacy-import",
            imagePath: nil,
            capturedMediaJSON: nil,
            queueState: .externalImport,
            timestamp: Date(),
            queueNextRetryAt: nil,
            queueLastErrorMessage: nil,
            queueNeedsAttention: true,
            approximateQueuedBytes: 0
        )
        let pendingVideo = QueuedScanSnapshot(
            id: "pending-video",
            imagePath: nil,
            capturedMediaJSON: CapturedMediaSnapshot(items: [
                .video(StoredVideoMediaReference(
                    .documents("queued-video.mp4")
                ))
            ]).jsonString,
            queueState: .pending,
            timestamp: Date(),
            queueNextRetryAt: nil,
            queueLastErrorMessage: nil,
            queueNeedsAttention: false,
            approximateQueuedBytes: 1
        )

        #expect(!attention.isAutomaticRecoveryEligible)
        #expect(attention.canRetryNow)
        #expect(staged.isAutomaticRecoveryEligible)
        #expect(!legacyImport.isAutomaticRecoveryEligible)
        #expect(!legacyImport.canRetryNow)
        #expect(!pendingVideo.isAutomaticRecoveryEligibleForCurrentNetwork(
            isOnline: false,
            isConstrained: false,
            allowsVideoUploads: true,
            isForcedVideoUpload: false
        ))
        #expect(!pendingVideo.isAutomaticRecoveryEligibleForCurrentNetwork(
            isOnline: true,
            isConstrained: true,
            allowsVideoUploads: true,
            isForcedVideoUpload: true
        ))
        #expect(!pendingVideo.isAutomaticRecoveryEligibleForCurrentNetwork(
            isOnline: true,
            isConstrained: false,
            allowsVideoUploads: false,
            isForcedVideoUpload: false
        ))
        #expect(pendingVideo.isAutomaticRecoveryEligibleForCurrentNetwork(
            isOnline: true,
            isConstrained: false,
            allowsVideoUploads: false,
            isForcedVideoUpload: true
        ))
        #expect(pendingVideo.isAutomaticRecoveryEligibleForCurrentNetwork(
            isOnline: true,
            isConstrained: false,
            allowsVideoUploads: true,
            isForcedVideoUpload: false
        ))
        #expect(staged.isAutomaticRecoveryEligibleForCurrentNetwork(
            isOnline: true,
            isConstrained: false,
            allowsVideoUploads: false,
            isForcedVideoUpload: false
        ))
        #expect(
            !QueuedScanContext(
                id: "legacy-import",
                capturedMediaItems: [],
                queueState: .externalImport,
                timestamp: Date(),
                queueNeedsAttention: true
            ).canRetryNow
        )
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

    // MARK: - Test 5: audio-only scans prefer reference-thumbnail fallback instead of archived visuals

    @Test func testAudioOnlyScansPreferReferenceFallback() throws {
        let audioJson = try makeCapturedMediaJSON([.audio("field-recording.wav")])
        let record = LocalScanRecord(
            speciesId: UUID().uuidString,
            scientificName: "Buteo jamaicensis",
            commonName: "Red-tailed Hawk",
            capturedMediaJSON: audioJson,
            coverImagePath: nil,
            semanticTags: [],
            hazardType: "none",
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "wild"
        )

        let presentation = record.scanThumbnailPresentation

        #expect(presentation.imagePath == nil, "Audio-only scans should not advertise a local image path")
        #expect(presentation.fallbackImageUrl == nil, "The test scan starts without a persisted reference image")
        #expect(presentation.audioPath == "field-recording.wav", "The audio path remains available to non-library thumbnail consumers and scan detail")
        #expect(presentation.hasAudio, "Audio-only scans should advertise their recording badge")
        #expect(presentation.placeholderStyle == .pendingReference(.audio), "Audio-only biological scans should wait for a reference image instead of rendering as archived")
        #expect(ScanThumbnailBackfillCandidate(record: record) != nil, "Audio-only biological scans without images should be eligible for thumbnail backfill")
    }

    // MARK: - Test 6: unknown non-visual scans surface a terminal placeholder and skip backfill

    @Test func testUnknownDescribeScansSkipThumbnailBackfill() throws {
        let descriptionJson = try makeCapturedMediaJSON([.description(ObservationContext(freeText: "brown bird in shadows"))])
        let record = LocalScanRecord(
            speciesId: UUID().uuidString,
            scientificName: "Taxonomy Unavailable",
            commonName: "Unknown Subject",
            capturedMediaJSON: descriptionJson,
            coverImagePath: nil,
            semanticTags: [],
            hazardType: "none",
            isBiological: true,
            isLiveCapture: false,
            isInvasive: false,
            ecologyType: "unknown"
        )

        let presentation = record.scanThumbnailPresentation

        #expect(presentation.audioPath == nil, "Describe-only scans should not attempt to render an audio spectrogram thumbnail")
        #expect(presentation.placeholderStyle == .unavailableReference(.describe), "Unknown non-visual scans should show a non-visual terminal placeholder instead of pretending a fallback image exists")
        #expect(ScanThumbnailBackfillCandidate(record: record) == nil, "Unknown subjects should not enter the background reference-thumbnail backfill queue")
    }

    @Test func testRemoteVisualFailureOnlyUsesArchiveCopyForExplicitlyArchivedRecords() {
        let record = LocalScanRecord(
            speciesId: UUID().uuidString,
            scientificName: "Danaus plexippus",
            commonName: "Monarch",
            coverImagePath: "https://media.merian.app/scans/monarch.webp",
            isLocallyArchived: false
        )

        #expect(!ScanThumbnail(record: record).isArchivedVisual)

        record.isLocallyArchived = true

        #expect(ScanThumbnail(record: record).isArchivedVisual)
    }
}
