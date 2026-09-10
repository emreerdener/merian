import Foundation

struct LocalScanMediaRecoverySnapshot: Equatable, Sendable {
    let scanID: String
    let timestamp: Date?
    let coverImagePath: String?
    let items: [SerializedMediaItem]

    init(record: LocalScanRecord) {
        scanID = record.id
        timestamp = record.timestamp
        coverImagePath = record.coverImagePath
        items = record.serializedCapturedMediaItems
    }

    init(response: HistoricalScanResponse) {
        let hydratedItems = CapturedMediaSnapshot.cloudHydratedItems(
            capturedMediaItems: response.capturedMediaItems,
            imageStorageURLs: response.image_storage_urls,
            videoStorageURLs: response.video_storage_urls,
            audioStorageURLs: response.audio_storage_urls,
            observationContext:
                response.user_observation_context?.observationContext
        )

        scanID = response.id
        timestamp = Self.historicalDate(response.created_at)
        coverImagePath = CapturedMediaSnapshot(
            items: hydratedItems
        ).primaryImagePath ?? response.image_storage_urls?.first
        items = hydratedItems
    }

    private static func historicalDate(_ timestamp: String?) -> Date? {
        guard let timestamp else { return nil }
        return DateUtilities.iso8601FractionalFormatter.date(from: timestamp)
            ?? DateUtilities.iso8601Formatter.date(from: timestamp)
    }
}
