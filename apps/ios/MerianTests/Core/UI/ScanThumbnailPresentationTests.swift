import Foundation
import Testing

@testable import Merian

@MainActor
struct ScanThumbnailPresentationTests {
    @Test func audioOnlyScanPrefersReferenceFallback() throws {
        let record = LocalScanRecord(
            speciesId: UUID().uuidString,
            scientificName: "Buteo jamaicensis",
            commonName: "Red-tailed Hawk",
            capturedMediaJSON: try mediaJSON([
                .audio("field-recording.wav")
            ]),
            coverImagePath: nil,
            semanticTags: [],
            hazardType: "none",
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "wild"
        )

        let presentation = record.scanThumbnailPresentation

        #expect(presentation.imagePath == nil)
        #expect(presentation.fallbackImageUrl == nil)
        #expect(presentation.audioPath == "field-recording.wav")
        #expect(presentation.hasAudio)
        #expect(presentation.placeholderStyle == .pendingReference(.audio))
        #expect(ScanThumbnailBackfillCandidate(record: record) != nil)
    }

    @Test func unknownDescribeScanSkipsThumbnailBackfill() throws {
        let record = LocalScanRecord(
            speciesId: UUID().uuidString,
            scientificName: "Taxonomy Unavailable",
            commonName: "Unknown Subject",
            capturedMediaJSON: try mediaJSON([
                .description(
                    ObservationContext(
                        freeText: "brown bird in shadows"
                    )
                )
            ]),
            coverImagePath: nil,
            semanticTags: [],
            hazardType: "none",
            isBiological: true,
            isLiveCapture: false,
            isInvasive: false,
            ecologyType: "unknown"
        )

        let presentation = record.scanThumbnailPresentation

        #expect(presentation.audioPath == nil)
        #expect(
            presentation.placeholderStyle
                == .unavailableReference(.describe)
        )
        #expect(ScanThumbnailBackfillCandidate(record: record) == nil)
    }

    @Test func remoteFailureUsesArchiveCopyOnlyForArchivedRecord() {
        let record = LocalScanRecord(
            speciesId: UUID().uuidString,
            scientificName: "Danaus plexippus",
            commonName: "Monarch",
            coverImagePath:
                "https://media.merian.app/scans/monarch.webp",
            isLocallyArchived: false
        )

        #expect(!ScanThumbnail(record: record, isOnline: true).isArchivedVisual)

        record.isLocallyArchived = true

        #expect(ScanThumbnail(record: record, isOnline: true).isArchivedVisual)
    }

    private func mediaJSON(
        _ items: [SerializedMediaItem]
    ) throws -> String {
        let data = try JSONEncoder().encode(items)
        return try #require(String(bytes: data, encoding: .utf8))
    }
}
