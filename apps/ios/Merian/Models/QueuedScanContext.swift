import Foundation

/// A value-type snapshot of all data the insight sheet chain needs from an `OfflineQueuedScan`.
///
/// **Why this exists**: Every view in the queued-scan path (`LibraryView`,
/// `InsightSheetView`, `InsightSheetViewModel`, `QueuedContentView`) previously held a live
/// `OfflineQueuedScan` reference. When the queued scan is deleted, SwiftData tears down its
/// backing store. The pushed destination remains active while the completed result replaces
/// queued content, so accessing ANY unfaulted attribute on that detached model would crash.
///
/// Snapshotting all needed data into this value type at tap time (while the object is live)
/// breaks the direct observation dependency. SwiftUI never registers a tracking dependency on
/// the `OfflineQueuedScan` model's properties, so no re-evaluation happens on deletion.
struct QueuedScanContext: Identifiable, Equatable {
    let id: String
    let capturedMediaItems: [SerializedMediaItem]
    let queueState: ScanQueueState
    let timestamp: Date
    let locationName: String?
    let weatherTemperatureF: Double?
    let weatherCondition: String?
    let gpsElevation: Double?
    let gpsLatitude: Double?
    let gpsLongitude: Double?
    let queueAttemptCount: Int
    let queueNextRetryAt: Date?
    let queueLastErrorCode: String?
    let queueLastErrorMessage: String?
    let queueNeedsAttention: Bool
    let approximateQueuedBytes: Int64
    let visualMediaItemsJSON: String?

    var capturedMediaSnapshot: CapturedMediaSnapshot {
        CapturedMediaSnapshot(items: capturedMediaItems)
    }

    var capturedMediaJSON: String? {
        capturedMediaSnapshot.jsonString
    }

    var activeScanMedia: ActiveScanMedia {
        var media = capturedMediaSnapshot.activeScanMedia
        guard let visualMediaItemsJSON,
              let data = visualMediaItemsJSON.data(using: .utf8),
              let descriptors = try? JSONDecoder().decode([IdentifyVisualMediaItem].self, from: data) else {
            return media
        }
        media.focusRegionsBySourceIndex = descriptors.focusRegionsBySourceIndex
        return media
    }

    var mediaKinds: [String] {
        var kinds: [String] = []
        let snapshot = capturedMediaSnapshot
        if !snapshot.thumbnailImagePaths.isEmpty { kinds.append("Images") }
        if !snapshot.videoPaths.isEmpty { kinds.append("Video") }
        if !snapshot.audioPaths.isEmpty { kinds.append("Audio") }
        if snapshot.descriptionText?.isEmpty == false { kinds.append("Text") }
        return kinds
    }

    var canRetryNow: Bool {
        queueState == .failed ||
            queueNeedsAttention ||
            (
                queueNextRetryAt != nil &&
                (queueState == .pending || queueState == .staged)
            )
    }

    /// Initialises the context by resolving all attribute faults on the live `OfflineQueuedScan`.
    /// Must be called while the object is still alive (before any `context.delete()`).
    init(from scan: OfflineQueuedScan) {
        self.init(
            id: scan.id,
            capturedMediaItems: scan.serializedCapturedMediaItems,
            queueState: scan.queueState,
            timestamp: scan.timestamp,
            locationName: scan.locationName,
            weatherTemperatureF: scan.weatherTemperatureF,
            weatherCondition: scan.weatherCondition,
            gpsElevation: scan.gpsElevation,
            gpsLatitude: scan.gpsLatitude,
            gpsLongitude: scan.gpsLongitude,
            queueAttemptCount: scan.queueAttemptCount,
            queueNextRetryAt: scan.queueNextRetryAt,
            queueLastErrorCode: scan.queueLastErrorCode,
            queueLastErrorMessage: scan.queueLastErrorMessage,
            queueNeedsAttention: scan.queueNeedsAttention,
            approximateQueuedBytes: Self.approximateQueuedBytes(
                mediaItems: scan.serializedCapturedMediaItems,
                inferenceImagePaths: scan.inferenceImagePaths
            ),
            visualMediaItemsJSON: scan.visualMediaItemsJSON
        )
    }

    init(
        id: String,
        capturedMediaItems: [SerializedMediaItem],
        queueState: ScanQueueState,
        timestamp: Date,
        locationName: String? = nil,
        weatherTemperatureF: Double? = nil,
        weatherCondition: String? = nil,
        gpsElevation: Double? = nil,
        gpsLatitude: Double? = nil,
        gpsLongitude: Double? = nil,
        queueAttemptCount: Int = 0,
        queueNextRetryAt: Date? = nil,
        queueLastErrorCode: String? = nil,
        queueLastErrorMessage: String? = nil,
        queueNeedsAttention: Bool = false,
        approximateQueuedBytes: Int64 = 0,
        visualMediaItemsJSON: String? = nil
    ) {
        self.id = id
        self.capturedMediaItems = capturedMediaItems
        self.queueState = queueState
        self.timestamp = timestamp
        self.locationName = locationName
        self.weatherTemperatureF = weatherTemperatureF
        self.weatherCondition = weatherCondition
        self.gpsElevation = gpsElevation
        self.gpsLatitude = gpsLatitude
        self.gpsLongitude = gpsLongitude
        self.queueAttemptCount = queueAttemptCount
        self.queueNextRetryAt = queueNextRetryAt
        self.queueLastErrorCode = queueLastErrorCode
        self.queueLastErrorMessage = queueLastErrorMessage
        self.queueNeedsAttention = queueNeedsAttention
        self.approximateQueuedBytes = approximateQueuedBytes
        self.visualMediaItemsJSON = visualMediaItemsJSON
    }

    static func approximateQueuedBytes(
        mediaItems: [SerializedMediaItem],
        inferenceImagePaths: [String]? = nil
    ) -> Int64 {
        let snapshot = CapturedMediaSnapshot(items: mediaItems)
        let paths = snapshot.thumbnailImagePaths +
            snapshot.audioPaths +
            snapshot.videoPaths +
            (inferenceImagePaths ?? [])
        return approximateLocalBytes(paths: paths)
    }

    private static func approximateLocalBytes(paths: [String]) -> Int64 {
        let urls = Set(paths.compactMap(localURL(for:)))
        return urls.reduce(Int64(0)) { total, url in
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
            return total + size
        }
    }

    private static func localURL(for path: String) -> URL? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("http://"), !trimmed.hasPrefix("https://") else {
            return nil
        }
        if let url = URL(string: trimmed), url.isFileURL {
            return url
        }
        if trimmed.hasPrefix("/") {
            return URL(fileURLWithPath: trimmed)
        }
        return URL.documentsDirectory.appendingPathComponent(trimmed)
    }
}
