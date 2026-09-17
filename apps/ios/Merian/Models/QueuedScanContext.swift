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
struct QueuedScanContext: Identifiable, Equatable, Sendable {
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
        queueState.isManualRetryEligible(
            needsAttention: queueNeedsAttention,
            nextRetryAt: queueNextRetryAt
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
}
