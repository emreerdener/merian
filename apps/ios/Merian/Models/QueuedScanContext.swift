import Foundation

/// A value-type snapshot of all data the insight sheet chain needs from an `OfflineQueuedScan`.
///
/// **Why this exists**: Every view in the queued-scan path (`LibraryView`, `InsightSheetView`,
/// `InsightSheetViewModel`, `AnalyzingContentView`) previously held a live `OfflineQueuedScan`
/// reference. When the queued scan is deleted, SwiftData tears down
/// the object's backing store. During SwiftUI's subsequent dismissal animation (~300ms), the
/// view hierarchy is still active and re-evaluates computed properties — accessing ANY
/// unfaulted SwiftData attribute on the zombie causes the fatal "backing data detached" crash.
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

    var capturedMediaSnapshot: CapturedMediaSnapshot {
        CapturedMediaSnapshot(items: capturedMediaItems)
    }

    var capturedMediaJSON: String? {
        capturedMediaSnapshot.jsonString
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
            gpsLongitude: scan.gpsLongitude
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
        gpsLongitude: Double? = nil
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
    }
}
