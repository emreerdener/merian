import Foundation

/// A value-type snapshot of all data the insight sheet chain needs from an `OfflineQueuedScan`.
///
/// **Why this exists**: Every view in the queued-scan path (`LibraryView`, `InsightSheetView`,
/// `InsightSheetViewModel`, `AnalyzingContentView`) previously held a live `OfflineQueuedScan`
/// reference. When `flushOfflineQueuedScan` calls `context.delete(scan)`, SwiftData tears down
/// the object's backing store. During SwiftUI's subsequent dismissal animation (~300ms), the
/// view hierarchy is still active and re-evaluates computed properties — accessing ANY
/// unfaulted SwiftData attribute on the zombie causes the fatal "backing data detached" crash.
///
/// Snapshotting all needed data into this value type at tap time (while the object is live)
/// breaks the direct observation dependency. SwiftUI never registers a tracking dependency on
/// the `OfflineQueuedScan` model's properties, so no re-evaluation happens on deletion.
struct QueuedScanContext: Identifiable, Equatable {
    let id: String
    let localImagePaths: [String]
    let timestamp: Date
    let locationName: String?
    let weatherTemperatureF: Double?
    let weatherCondition: String?
    let gpsElevation: Double?
    let gpsLatitude: Double?
    let gpsLongitude: Double?

    /// Initialises the context by resolving all attribute faults on the live `OfflineQueuedScan`.
    /// Must be called while the object is still alive (before any `context.delete()`).
    init(from scan: OfflineQueuedScan) {
        self.id = scan.id
        self.localImagePaths = scan.localImagePaths
        self.timestamp = scan.timestamp
        self.locationName = scan.locationName
        self.weatherTemperatureF = scan.weatherTemperatureF
        self.weatherCondition = scan.weatherCondition
        self.gpsElevation = scan.gpsElevation
        self.gpsLatitude = scan.gpsLatitude
        self.gpsLongitude = scan.gpsLongitude
    }
}
